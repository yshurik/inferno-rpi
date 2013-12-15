implement Usbd;

include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;
include "lock.m";
	lock: Lock;
	Semaphore: import lock;
include "arg.m";
	arg: Arg;

include "usb.m";
	usb: Usb;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Usbd: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

usbbase: string;
verbose: int;
usbdebug: int;
stderr: ref Sys->FD;
sema: ref Semaphore;

obt() { sema.obtain(); }
rel() { sema.release(); }

pollms: con 1000;

Nep	:con 16;	# max. endpoints per usb device & per interface
Nconf	:con 16;	# max. configurations per usb device
Naltc	:con 16;	# max. alt configurations per interface
Niface	:con 16;
Nddesc	:con 8*Nep;	# max. device-specific descriptors per usb device
Uctries :con 4;
Ucdelay :con 50; # delay before retrying

# request type
Rh2d	:con 0<<7;		# host to device
Rd2h	:con 1<<7;		# device to host

Maxdevconf :con 4 * 1024;

Fhublocalpower		:con 0;
Fhubovercurrent		:con 1;

Fportconnection		:con 0;
Fportenable		:con 1;
Fportsuspend		:con 2;
Fportovercurrent	:con 3;
Fportreset		:con 4;
Fportpower		:con 8;
Fportlowspeed		:con 9;
Fcportconnection	:con 16;
Fcportenable		:con 17;
Fcportsuspend		:con 18;
Fcportovercurrent	:con 19;
Fcportreset		:con 20;
Fportindicator		:con 22;

PSpresent:	con 16r0001;
PSenable:	con 16r0002;
PSsuspend:	con 16r0004;
PSovercurrent:	con 16r0008;
PSreset:	con 16r0010;
PSpower:	con 16r0100;
PSslow:		con 16r0200;
PShigh:		con 16r0400;

PSstatuschg:	con 16r10000;	# PSpresent changed
PSchange:	con 16r20000;	# PSenable changed

Spawndelay	:con 250;	# how often may we re-spawn a driver
Connectdelay	:con 500;	# how much to wait after a connect
Resetdelay	:con 20;	# how much to wait after a reset
Enabledelay	:con 20;	# how much to wait after an enable
Powerdelay	:con 100;	# after powering up ports
Pollms		:con 250;	# port poll interval
Chgdelay	:con 100;	# waiting for port become stable
Chgtmout	:con 1000;	# ...but at most this much

Pdisabled	:con 0;		# must be 0
Pattached	:con 1;
Pconfiged	:con 2;

# standard requests
Rgetstatus	:con 0;
Rclearfeature	:con 1;
Rsetfeature	:con 3;
Rsetaddress	:con 5;
Rgetdesc	:con 6;
Rsetdesc	:con 7;
Rgetconf	:con 8;
Rsetconf	:con 9;
Rgetiface	:con 10;
Rsetiface	:con 11;
Rsynchframe	:con 12;

# dev classes
Clnone		:con 0;	# not in usb
Claudio		:con 1;
Clcomms		:con 2;
Clhid		:con 3;
Clprinter	:con 7;
Clstorage	:con 8;
Clhub		:con 9;
Cldata		:con 10;

# standard descriptor sizes
Ddevlen		:con 18;
Dconflen	:con 9;
Difacelen	:con 9;
Deplen		:con 7;

# descriptor types
Ddev		:con 1;
Dconf		:con 2;
Dstr		:con 3;
Diface		:con 4;
Dep		:con 5;
Dreport		:con 16r22;
Dfunction	:con 16r24;
Dphysical	:con 16r23;

Dhub		:con 16r29;	# hub descriptor type
Dhublen 	:con 9;		# hub descriptor length

# feature selectors
Fdevremotewakeup	:con 1;
Fhalt			:con 0;

# endpoint direction
Ein		:con 0;
Eout		:con 1;
Eboth		:con 2;

# endpoint type
Econtrol	:con 0;
Eiso		:con 1;
Ebulk		:con 2;
Eintr		:con 3;

# endpoint isotype
Eunknown	:con 0;
Easync		:con 1;
Eadapt		:con 2;
Esync		:con 3;

Hub: adt {
	nport, pwrmode, compound :int;
	pwrms: int;			# time to wait in ms
	maxcurrent: int;		# after powering port
	leds: int; 			# has port indicators?
	maxpkt: int;
	port: cyclic array of ref Port;
	failed: int;			# I/O error while enumerating
	isroot: int;			# set if root hub
	dev: ref Dev;			# for this hub
	next: cyclic ref Hub;		# in list of hubs */
};
mkhub(): ref Hub { h := ref Hub(0,0,0,0,0,0,0,nil,0,0,nil,nil); return h; }

Port: adt {
	state: int;		# state of the device
	sts: int;		# old port status
	removable: int;
	pwrctl: int;
	dev: ref Dev;		# attached device (if non-nil)
	hub: cyclic ref Hub;	# non-nil if hub attached
	devnb: int;		# device number
	#uvlong	*devmaskp;	/* ptr to dev mask */
};
mkport(): ref Port { p := ref Port(0,0,0,0,nil,nil,0); return p; }

########################### dev part ##########################

# Usb device (when used for ep0s) or endpoint.
# RC: One ref because of existing, another one per ogoing I/O.
# per-driver resources (including FS if any) are released by aux
# once the last ref is gone. This may include other Devs using
# to access endpoints for actual I/O.

Dev: adt {
	dir: string;		# path for the endpoint dir
	id: int;		# usb id for device or ep. number
	dfd: ref Sys->FD;	# descriptor for the data file
	cfd: ref Sys->FD;	# descriptor for the control file
	maxpkt: int;		# cached from usb description
#Ref     nerrs;          /* number of errors in requests */
	usb: ref Usbdev;	# USB description */
#void*   aux;            /* for the device driver */
#void    (*free)(void*); /* idem. to release aux */
};

#
# device description as reported by USB (unpacked).
#
Usbdev: adt {
	csp: int;		# USB class/subclass/proto
	vid: int;		# vendor id
	did: int;		# product (device) id
	dno: int;		# device release number
	vendor: string;
	product: string;
	serial: string;
	vsid: int;
	psid: int;
	ssid: int;
	class: int;		# from descriptor
	nconf: int;		# from descriptor
	ep: array of ref Ep;		# Nep all endpoints in device
	conf: array of ref Conf;	# Nconf configurations
	ddesc: array of ref Desc;	# Nddesc (raw) device specific descriptors
};
mkusbdev(): ref Usbdev {
	u := ref Usbdev;
	u.ep = array[Nep] of ref Ep;
	u.conf = array[Nconf] of ref Conf;
	u.ddesc = array[Nddesc] of ref Desc;
	u.csp = u.vid = u.did = u.dno = u.vsid = u.psid = u.class = u.nconf = 0;
	return u;
}

Ep: adt {
	addr: int;		# endpt address, 0-15 (|0x80 if Ein)
	dir: int;		# direction, Ein/Eout
	typ: int;		# Econtrol, Eiso, Ebulk, Eintr
	isotype: int;		# Eunknown, Easync, Eadapt, Esync
	id :int;
	maxpkt :int;		# max. packet size
	ntds: int;		# nb. of Tds per µframe
	#conf: cyclic ref Conf;		# the endpoint belongs to
	iface: cyclic ref Iface;	# the endpoint belongs to
};
mkep(d: ref Usbdev, id: int): ref Ep {
	ep := ref Ep; ep.id = id;
	d.ep[id] = ep;
	return ep;
}

Altc: adt {
	attrib: int;
	interval: int;
#	void*	aux;		/* for the driver program */
};

Iface: adt {
	id: int;		# interface number */
	csp: int;		# USB class/subclass/proto */
	altc: array of ref Altc;
	ep: cyclic array of ref Ep;
#	void*	aux;		/* for the driver program */
};

Conf: adt {
	cval: int;		# value for set configuration
	attrib: int;
	milliamps: int;		# maximum power in this config.
	iface: array of ref Iface;
};

Desc: adt {
	conf: ref Conf;		# where this descriptor was read.
	iface: ref Iface;	# last iface before desc in conf.
	ep: ref Ep;		# last endpt before desc in conf.
	altc: ref Altc;		# last alt.c. before desc in conf.
	data: array of byte;	# unparsed standard USB descriptor.
};

memset(buf: array of byte, v: int)
	{ for (x :=0; x < len buf; x++) buf[x] = byte v; }

nameid(s: string): int { # epN.M -> N
	l,n: string; i: int;
	(l,nil) = str->splitstrl(s,".");
	if (l ==s) return -1;
	(nil,n) = str->splitstrr(l,"p");
	if (n ==s) return -1;
	(i,nil) = str->toint(n,10);
	return i;
}

opendev(fnm: string): ref Dev {
	d := ref Dev;
	d.dfd = nil;
	d.dir = fnm;;
	d.cfd = sys->open(d.dir+"/ctl", sys->ORDWR);
	d.id = nameid(fnm);
	if(d.cfd == nil){
		sys->fprint(stderr, "usbd: can't open endpoint %s: %r", d.dir);
		return nil;
	}
	#sys->fprint(stderr, "usbd: opendev %s\n", fnm);
	return d;
}

opendevdata(d: ref Dev, mode: int): ref Sys->FD {
	#sys->fprint(stderr, "usbd: opening %s\n", d.dir+"/data");
	d.dfd = sys->open(d.dir+"/data", mode);
	return d.dfd;
}

devctl(d: ref Dev, s: string):int {
	#sys->fprint(stderr, "devctl: %s\n", s);
	buf := sys->aprint("%s",s);
	return sys->write(d.cfd, buf, len buf);
}

hex(buf: array of byte): string {
	s := "";
	for(i:=0; i< len buf; ++i) {
		s += sys->sprint("%2x ",int buf[i]);
	}
	return s;
}

cmdreq(d: ref Dev, typ, req, value, index: int, outbuf: array of byte, count: int): int {
	additional: int;
	if (outbuf != nil) {
		additional = len outbuf;
		# if there is an outbuf, then the count sent must be length of the payload
		# this assumes that RH2D is set
		count = additional;
	}
	else additional = 0;
	buf := array[8 + additional] of byte;
	buf[0] = byte typ;
	buf[1] = byte req;
	usb->put2(buf[2:], value);
	usb->put2(buf[4:], index);
	usb->put2(buf[6:], count);
	if (additional)
		buf[8:] = outbuf;
	#sys->fprint(stderr, "%s: %d val %d|%d idx %d cnt %d out[%d] %s\n",
	#			d.dir, req, value>>8, value&16rFF,
	#			index, count, additional+8, hex(buf));
	#sys->fprint(stderr, "%s: out: %s\n",
	#			d.dir, hex(buf));
	obt();
	rv := sys->write(d.dfd, buf, len buf);
	rel();
	if (rv < 0)
		return -1;
	if (rv != len buf)
		return -1;
	return rv;
}

cmdrep(d: ref Dev, buf: array of byte, nb: int): int {
	inbuf := array[nb] of { * => byte 0 };
	memset(inbuf,16rDD);
	obt();
	nb = sys->read(d.dfd, inbuf, nb);
	rel();

	buf[0:] = inbuf[0:nb];

	if(int inbuf[0]== 16r55) {
		sys->fprint(stderr, "%s: inp: %s\n",
					d.dir, hex(buf[:nb]));

		sys->fprint(stderr,"STOP!!!!\n");
		for(;;) sys->sleep(1000);
	}

	return nb;
}

usbcmd(d: ref Dev, ctype: int, req: int, value: int, index: int, data: array of byte, count: int): int {
	i,nerr: int;
	err: string;

	#
	# Some devices do not respond to commands some times.
	# Others even report errors but later work just fine. Retry.
	#
	r := -1;
	for(i = nerr = 0; i < Uctries; i++){
		if(ctype & Rd2h)
			r = cmdreq(d, ctype, req, value, index, nil, count);
		else
			r = cmdreq(d, ctype, req, value, index, data, count);
		if(r >0){
			if((ctype & Rd2h) ==0)
				break;
			r = cmdrep(d, data, count);
			if(r >0) break;
			if(r ==0) sys->werrstr("no data from device");
		}
		nerr++;
		if(err =="") err = sys->sprint("%r");
		sys->sleep(Ucdelay);
	}
	if(r >0 && i >=2)
		# let the user know the device is not in good shape
		sys->fprint(stderr, "usbd: usbcmd: %s: required %d attempts (%s)\n", d.dir, i, err);
	return r;
}

unstall(dev: ref Dev, ep: ref Dev, dir: int): int {
	if(dir == Ein)
		dir = 16r80;
	else	dir = 0;
	r := Rh2d|usb->Rstandard|usb->Rendpt;
	if(usbcmd(dev, r, usb->CLEAR_FEATURE, Fhalt, ep.id|dir, nil, 0)<0){
		sys->werrstr(sys->sprint("unstall: %s: %r", ep.dir));
		return -1;
	}
	if(devctl(ep, "clrhalt") < 0){
		sys->werrstr(sys->sprint("clrhalt: %s: %r", ep.dir));
		return -1;
	}
	return 0;
}

parsedev(xd: ref Dev, b: array of byte, n: int): int {
	d := xd.usb;
	b = b[:n];
	bLen := int b[0];
	bTyp := int b[1];

	if(usbdebug>1){
		sys->fprint(stderr, "usbd: parsedev %s: %s\n", xd.dir, hex(b));
	}
	if(bLen < usb->DDEVLEN){
		sys->werrstr(sys->sprint("short dev descr. (%d < %d)", bLen, usb->DDEVLEN));
		return -1;
	}
	if(bTyp != Ddev){
		sys->werrstr(sys->sprint("%d is not a dev descriptor", bTyp));
		return -1;
	}
	d.csp = ((int b[4]) | (int b[5])<<8 | (int b[6])<<16);
	d.ep[0].maxpkt = xd.maxpkt = int b[7];
	d	.class = int b[4];
	d.nconf = int b[17];
	if(d.nconf ==0)
		sys->fprint(stderr, "usbd: %s: no configurations\n", xd.dir);
	d.vid = usb->get2(b[8:]);
	d.did = usb->get2(b[10:]);
	d.dno = usb->get2(b[12:]);
	d.vsid = int b[14];
	d.psid = int b[15];
	d.ssid = int b[16];
	if(n > usb->DDEVLEN && usbdebug>1)
		sys->fprint(stderr, "usbd: %s: parsedev: %d bytes left",
			xd.dir, n - usb->DDEVLEN);
	return usb->DDEVLEN;
}

loaddevstr(d: ref Dev, sid: int): string {
	buf := array[128] of byte;
	if(sid ==0) return "none";
	typ := Rd2h|usb->Rstandard|usb->Rdevice;
	nr := usbcmd(d, typ, usb->GET_DESCRIPTOR, usb->STRING<<8|sid, 0, buf, len buf);
	return string buf[0: nr];
}

loaddevdesc(d: ref Dev): int {
	buf := array[usb->DDEVLEN+255] of byte;
	typ := Rd2h|usb->Rstandard|usb->Rdevice;
	nr := len buf;
	memset(buf, 0);
	if((nr=usbcmd(d, typ, usb->GET_DESCRIPTOR, Ddev<<8|0, 0, buf, nr)) <0)
		return -1;
	#
	# Several hubs are returning descriptors of 17 bytes, not 18.
	# We accept them and leave number of configurations as zero.
	# (a get configuration descriptor also fails for them!)
	#
	if(nr < usb->DDEVLEN){
		sys->fprint(stderr, "usbd: %s: warning: device with short descriptor\n",
			d.dir);
		if(nr < usb->DDEVLEN-1){
			sys->werrstr(sys->sprint("short device descriptor (%d bytes)", nr));
			return -1;
		}
	}
	d.usb = mkusbdev();

	ep0 := mkep(d.usb, 0);
	ep0.dir = Eboth;
	ep0.typ = Econtrol;
	ep0.maxpkt = d.maxpkt = 8; # a default
	nr = parsedev(d, buf, nr);
	if(nr >= 0){
		d.usb.vendor = loaddevstr(d, d.usb.vsid);
		if(d.usb.vendor !="none"){
			d.usb.product = loaddevstr(d, d.usb.psid);
			d.usb.serial = loaddevstr(d, d.usb.ssid);
		}
	}
	return nr;
}

dname(dtype: int): string {
	case dtype {
	Ddev		=> return "device";
	usb->CONFIGURATION	=> return "config";
	usb->STRING		=> return "string";
	usb->INTERFACE		=> return "interface";
	usb->ENDPOINT		=> return "endpoint";
	usb->REPORT		=> return "report";
	usb->PHYSICAL		=> return "phys";
	}
	return "desc";
}

parseiface(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): (int, ref Iface, ref Altc) {
	class, subclass, proto: int;
	ifid, altid: int;
	ip: ref Iface;
	b = b[:n];

	if(n < Difacelen){
		sys->werrstr("short interface descriptor");
		return (-1,nil,nil);
	}
	ifid = int b[2];
	if(ifid < 0 || ifid >= len c.iface){
		sys->werrstr(sys->sprint("bad interface number %d", ifid));
		return (-1,nil,nil);
	}
	if(c.iface[ifid] ==nil)
		c.iface[ifid] = ref Iface;
	ip = c.iface[ifid];
	class = int b[5];
	subclass = int b[6];
	proto = int b[7];
	ip.csp = (class | subclass<<8 | proto<<16);
	if(d.csp ==0)			# use csp from 1st iface
		d.csp = ip.csp;		# if device has none
	if(d.class == 0)
		d.class = class;
	ip.id = ifid;
	if(c == d.conf[0] && ifid == 0)	# ep0 was already there
		d.ep[0].iface = ip;
	altid = int b[3];
	if(altid < 0 || altid >= len ip.altc){
		sys->werrstr(sys->sprint("bad alternate conf. number %d", altid));
		return (-1,nil,nil);
	}
	if(ip.altc[altid] ==nil)
		ip.altc[altid] = ref Altc;
	return (Difacelen, ip, ip.altc[altid]);
}

parseendpt(d: ref Usbdev, c: ref Conf, ip: ref Iface, altc: ref Altc, b: array of byte, n: int): (int, ref Ep) {
	i, dir, epid: int;
	ep: ref Ep;
	epp: ref Ep;
	b = b[:n];

	if(n < Deplen){
		sys->werrstr("short endpoint descriptor");
		return (-1,nil);
	}
	altc.attrib = int b[3];
	altc.interval = int b[6];

	epid = int b[2] & 16rF;
	if(int b[2] & 16r80)
		dir = Ein;
	else
		dir = Eout;
	ep = d.ep[epid];
	if(ep ==nil){
		ep = mkep(d, epid);
		ep.dir = dir;
	}else if((ep.addr & 16r80) != (int b[2] & 16r80))
		ep.dir = Eboth;
	ep.maxpkt = usb->get2(b[4:]);
	ep.ntds = 1 + ((ep.maxpkt >> 11) & 3);
	ep.maxpkt &= 16r7FF;
	ep.addr = int b[2];
	ep.typ = int b[3] & 16r03;
	ep.isotype = (int b[3]>>2) & 16r03;
	#ep.conf = c;
	ep.iface = ip;
	for(i =0; i < len ip.ep; i++)
		if(ip.ep[i] == nil)
			break;
	if(i == len ip.ep){
		sys->werrstr(sys->sprint("parseendpt: bug: too many end points on interface with csp %#ux", ip.csp));
		sys->fprint(stderr, "usbd: %r\n");
		return (-1,nil);
	}
	epp = ip.ep[i] = ep;
	return (Dep, epp);
}

parsedesc(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): int {
	ip: ref Iface;
	ep: ref Ep;
	altc: ref Altc;
	tot := 0;
	ip = nil;
	ep = nil;
	altc = nil;
	b = b[:n];

	for(nd :=0; nd < len d.ddesc; nd++)
		if(d.ddesc[nd] ==nil)
			break;

	while(n >2 && int b[0] !=0 && int b[0] <=n){
		blen := int b[0];
		if(usbdebug>1){
			sys->fprint(stderr, "usbd:\t\tparsedesc %s %x[%d] %s\n",
				dname(int b[1]), int b[1], int b[0], hex(b[:blen]));
		}
		case int b[1] {
		Ddev => ;
		Dconf =>
			sys->werrstr(sys->sprint("unexpected descriptor %d", int b[1]));
			sys->fprint(stderr, "usbd: parsedesc: %r");
			break;
		Diface =>
			pin: int;
			(pin, ip, altc) = parseiface(d, c, b, n);
			if(pin <0){
				sys->fprint(stderr, "usbd: parsedesc: %r\n");
				return -1;
			}
			break;
		Dep =>
			if(ip == nil || altc == nil){
				sys->werrstr("unexpected endpoint descriptor");
				break;
			}
			pen :int;
			(pen,ep) = parseendpt(d, c, ip, altc, b, n);
			if(pen <0){
				sys->fprint(stderr, "usbd: parsedesc: %r\n");
				return -1;
			}
			break;
		* =>
			if(nd == len d.ddesc){
				sys->fprint(stderr, "usbd: parsedesc: too many device-specific descriptors for device %s %s\n",
					d.vendor, d.product);
				break;
			}
			d.ddesc[nd] = ref Desc;
			d.ddesc[nd].data = b;
			d.ddesc[nd].iface = ip;
			d.ddesc[nd].ep = ep;
			d.ddesc[nd].altc = altc;
			d.ddesc[nd].conf = c;
			++nd;
		}
		n -= blen;
		b = b[blen:];
		tot += blen;
	}
	return tot;
}

parseconf(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): int {
	b = b[:n];
	if(usbdebug>1)
		sys->fprint(stderr, "usbd:\tparseconf  %s\n", hex(b));
	if(int b[0] < usb->DCONFLEN){
		sys->werrstr("short configuration descriptor");
		return -1;
	}
	if(int b[1] != usb->CONFIGURATION){
		sys->werrstr("not a configuration descriptor");
		return -1;
	}
	c.iface = array[int b[4]] of ref Iface;
	for(i:=0; i< len c.iface; ++i) {
		c.iface[i] = ref Iface;
		c.iface[i].ep = array[Nep] of ref Ep;
		c.iface[i].altc = array[Naltc] of ref Altc;
	}
	c.cval = int b[5];
	c.attrib = int b[7];
	c.milliamps = int b[8] * 2;
	l := usb->get2(b[2:]);
	if(n < l){
		sys->werrstr("truncated configuration info");
		return -1;
	}
	n -= usb->DCONFLEN;
	bdesc := b[usb->DCONFLEN:];
	nr := 0;
	if(n >0 && (nr=parsedesc(d, c, bdesc, n)) <0)
		return -1;
	n -= nr;
	if(n > 0 && usbdebug>1)
		sys->fprint(stderr, "usbd:\tparseconf: %d bytes left\n", n);
	return l;
}

loaddevconf(d: ref Dev, n: int): int {
	if(n >= len d.usb.conf){
		sys->werrstr("loaddevconf: bug: out of configurations in device");
		sys->fprint(stderr, "usbd: %r\n");
		return -1;
	}
	buf := array[Maxdevconf] of byte;
	typ := Rd2h|usb->Rstandard|usb->Rdevice;
	nr := usbcmd(d, typ, usb->GET_DESCRIPTOR, usb->CONFIGURATION<<8|n, 0, buf, Maxdevconf);
	if(nr < usb->DCONFLEN){
		return -1;
	}
	if(d.usb.conf[n] ==nil) {
		d.usb.conf[n] = ref Conf;
		d.usb.conf[n].iface = array[Niface] of ref Iface;
	}
	nr = parseconf(d.usb, d.usb.conf[n], buf, nr);
	return nr;
}

configdev(d: ref Dev): int {
	if(d.dfd ==nil)
		opendevdata(d, sys->ORDWR);
	if(loaddevdesc(d) <0)
		return -1;
	for(i :=0; i < d.usb.nconf; i++)
		if(loaddevconf(d, i) <0)
			return -1;
	return 0;
}

classname(i: int): string {
	cnames := array[] of {
	"none", "audio", "comms", "hid", "",
	"", "", "printer", "storage", "hub", "data"};
	if (i>=0 && i< len cnames)
		return cnames[i];
	return sys->sprint("%d",i);
}

writeinfo(d: ref Dev) {
	ud := d.usb;
	#s := sys->sprint("info %s csp %#08ulx", classname(ud.class), ud.csp);
	s := sys->sprint("info %s csp %#08ux", classname(ud.class), ud.csp);
	for(i:=0; i< ud.nconf; ++i){
		c := ud.conf[i];
		if(c ==nil)
			break;
		for(j:=0; j< len c.iface; ++j){
			ifc := c.iface[j];
			if(ifc ==nil)
				break;
			if(ifc.csp != ud.csp)
				#s += sys->sprint(" csp %#08ulx", ifc.csp);
				s += sys->sprint(" csp %#08ux", ifc.csp);
		}
	}
	s += sys->sprint(" vid %06#x did %06#x", ud.vid, ud.did);
	s += sys->sprint(" %q %q", ud.vendor, ud.product);
	devctl(d, s);
}

startdev(pp: ref Port): int {
	#Devtab *dt;
	#Sarg *sa;
	#Channel *rc;

	d := pp.dev;
	ud := d.usb;

	writeinfo(d);
	sys->fprint(stderr,"usbd: start dev: class:%d,\t%d.%d.%d\n",ud.class, ud.vid,ud.did,ud.dno);

	if(ud.class == Clhub){
		#
		# Hubs are handled directly by this process avoiding
		# concurrent operation so that at most one device
		# has the config address in use.
		# We cancel kernel debug for these eps. too chatty.
		#
		pp.hub = newhub(d.dir, d);
		if(pp.hub ==nil)
			sys->fprint(stderr, "usbd: %s: %r\n", d.dir);
		#else
		#	sys->fprint(stderr, "usb/hub... ");
		if(usbdebug > 1)
			devctl(d, "debug 0"); # polled hubs are chatty
		if(pp.hub ==nil) return -1;
		return 0;
	}
#
#	for(dt = devtab; dt->name != nil; dt++)
#		if(devmatch(dt, ud))
#			break;
#	/*
#	 * From here on the device is for the driver.
#	 * When we return pp->dev contains a Dev just for us
#	 * with only the ctl open. Both devs are released on the last closedev:
#	 * driver's upon I/O errors and ours upon port dettach.
#	 */
#	if(dt->name == nil){
#		dprint(2, "%s: no configured entry for %s (csp %#08lx)\n",
#			argv0, d->dir, ud->csp);
#		close(d->dfd);
#		d->dfd = -1;
#		return 0;
#	}
#	sa = emallocz(sizeof(Sarg), 1);
#	sa->pp = pp;
#	sa->dt = dt;
#	rc = sa->rc = chancreate(sizeof(ulong), 1);
#	procrfork(startdevproc, sa, Stack, RFNOTEG);
#	if(recvul(rc) != 0)
#		free(sa);
#	chanfree(rc);
#	fprint(2, "usb/%s... ", dt->name);
#
	sys->sleep(Spawndelay); # in case we re-spawn too fast
	return 0;
}

closeconf(c: ref Conf) {
	if(c ==nil) return;
	for(i :=0; i< len c.iface; ++i)
		if(c.iface[i] != nil){
			for(a :=0; a< len c.iface[i].altc; ++a)
				c.iface[i].altc[a] = nil;
			c.iface[i] =nil;
		}
	c =nil;
}

closedev(d: ref Dev) {
	if(d==nil) return;
	sys->fprint(stderr, "usbd: closedev %s\n", d.dir);
	#if(d.free != nil)
	#	d.free(d.aux);
	d.cfd = d.dfd = nil;
	ud := d.usb;
	d.usb =nil;
	if(ud !=nil){
		for(i :=0; i < len ud.conf; ++i)
			closeconf(ud.conf[i]);
	}
	d =nil;
}

########################### end: dev part ##########################

hubfeature(h: ref Hub, port, f, on: int): int {
	cmd: int;
	if(on)	cmd = usb->SET_FEATURE;
	else	cmd = usb->CLEAR_FEATURE;
	return usbcmd(h.dev, Rh2d|usb->Rclass|usb->Rother, cmd, f, port, nil, 0);
}

configroothub(h: ref Hub) { # c!
	d := h.dev;
	h.nport = 2;
	h.maxpkt = 8;
	sys->seek(d.cfd, big 0, 0);

	buf := array [128] of byte;
	nr := sys->read(d.cfd, buf, len buf);
	if (nr>=0) {
		data := string buf[0: nr];
		(nil,s1) := str->splitstrr(data,"ports ");
		if (s1 ==data) sys->fprint(stderr, "usbd: %s: no port information\n", d.dir);
		else (h.nport,nil) = str->toint(s1,10);
		(nil,s2) := str->splitstrr(data,"maxpkt ");
		if (s2 ==s1) sys->fprint(stderr, "usbd: %s: no maxpkt information\n", d.dir);
		else (h.maxpkt,nil) = str->toint(s2,10);
	}
	h.port = array[h.nport+1] of ref Port;
	for(i:=0; i<h.nport+1; ++i) { h.port[i] = mkport(); }
	if (usbdebug)
		sys->fprint(stderr, "usbd: %s: ports %d maxpkt %d\n", d.dir, h.nport, h.maxpkt);
}

confighub(h: ref Hub): int {
	buf := array[128] of byte; # room for extra descriptors
	dd : array of byte;

	nr: int;
	d := h.dev.usb;

	Config: do {
	for(i := 0; i < len d.ddesc; i++)
		if(d.ddesc[i] ==nil)
			break;
		else if(int d.ddesc[i].data[1] == Dhub){ # bDescriptorType
			dd = d.ddesc[i].data;
			nr = Dhublen;
			break Config;
		}
	typ := Rd2h|usb->Rclass|usb->Rdevice;
	nr = usbcmd(h.dev, typ, Rgetdesc, Dhub<<8|0, 0, buf, len buf);
	if(nr < Dhublen){
		sys->fprint(stderr, "usbd: %s: getdesc hub: %r\n", h.dev.dir);
		return -1;
	}
	dd = buf;
	} while (0);
#Config:
	h.nport = int dd[2]; # bNbrPorts;
	nmap := 1 + h.nport/8;
	if(nr < 7 + 2*nmap){
		sys->fprint(stderr, "usbd: %s: descr. too small\n", h.dev.dir);
		return -1;
	}
	h.port = array[h.nport+1] of ref Port;
	for(i:=0; i<h.nport+1; ++i) { h.port[i] = mkport(); }

	h.pwrms = int dd[5] *2; # bPwrOn2PwrGood*2;
	if(h.pwrms < Powerdelay)
		h.pwrms = Powerdelay;
	h.maxcurrent = int dd[6]; # bHubContrCurrent;
	h.pwrmode = int dd[3] & 3; # wHubCharacteristics
	h.compound = (int dd[3] & (1<<2))!=0; # wHubCharacteristics
	h.leds = (int dd[3] & (1<<7)) != 0;
	for(i=1; i <= h.nport; i++){
		pp := h.port[i];
		offset := i/8;
		mask := 1<<(i%8);
		pp.removable = (int dd[7+offset] & mask) != 0; # DeviceRemovable
		pp.pwrctl = (int dd[7+nmap+offset] & mask) != 0; # DeviceRemovable
	}
	return 0;
}

hubs : list of ref Hub;
nhubs := 0;

newhub(fnm: string, d: ref Dev): ref Hub {
	h := mkhub();
	h.isroot = (d ==nil);
	fail: do {
		if(h.isroot){
			h.dev = opendev(fnm);
			if(h.dev ==nil){
				sys->fprint(stderr, "usbd: opendev: %s: %r", fnm);
				break fail;
			}
			if(opendevdata(h.dev, sys->ORDWR) ==nil){
				sys->fprint(stderr, "usbd: opendevdata: %s: %r\n", fnm);
				break fail;
			}

			configroothub(h); # never fails
		}
		else {
			h.dev = d;
			if(confighub(h) <0){
				sys->fprint(stderr, "usbd: %s: config: %r\n", fnm);
				break fail;
			}
		}
		if(h.dev ==nil){
			sys->fprint(stderr, "usbd: opendev: %s: %r\n", fnm);
			break fail;
		}
		devctl(h.dev, "hub");
		ud := h.dev.usb;
		if(h.isroot)
			devctl(h.dev, sys->sprint("info roothub csp %#08ux ports %d", 16r000009, h.nport));
		else {
			#devctl(h.dev, sys->sprint("info hub csp %#08ulx ports %d %q %q",
			devctl(h.dev, sys->sprint("info hub csp %#08ux ports %d %q %q",
				ud.csp, h.nport, ud.vendor, ud.product));
			for(i := 1; i <= h.nport; i++)
				if(hubfeature(h, i, Fportpower, 1) < 0)
					sys->fprint(stderr, "usbd: %s: power: %r\n", fnm);
			sys->sleep(h.pwrms);
			for(i = 1; i <= h.nport; i++)
				if(h.leds != 0)
					hubfeature(h, i, Fportindicator, 1);
		}
		if (len hubs) h.next = hd hubs; else h.next = nil;
		hubs = h::hubs;
		nhubs++;

		if (usbdebug){
			sys->fprint(stderr, "usbd: hub allocated:");
			sys->fprint(stderr, " ports %d pwrms %d max curr %d pwrm %d cmp %d leds %d\n",
				h.nport, h.pwrms, h.maxcurrent,
				h.pwrmode, h.compound, h.leds);
		}

		return h;
	} while (0);
#fail:
	if(d !=nil) devctl(d, "detach");
	sys->fprint(stderr, "usbd: hub %s failed to start\n", fnm);
	return nil;
}

#
# If during enumeration we get an I/O error the hub is gone or
# in pretty bad shape. Because of retries of failed usb commands
# (and the sleeps they include) it can take a while to detach all
# ports for the hub. This detaches all ports and makes the hub void.
# The parent hub will detect a detach (probably right now) and
# close it later.
#
hubfail(h: ref Hub) { for(i := 1; i <= h.nport; i++) portdetach(h, i); h.failed = 1; }

closehub(h: ref Hub) {
	ch,ph: ref Hub;
	hds: list of ref Hub;
	nh := hubs;
	sys->fprint(stderr, "usbd: closing hub %s\n", h.dev.dir);

	for(nh = hubs; nh != nil; nh = tl nh) {
		ch = hd nh;
		if(ch ==h) {
			if(ph !=nil) ph.next = ch.next;
			for(;hds !=nil; hds = tl hds)
				nh = (hd hds)::nh;
			break;
		}
		hds = ch::nh;
		ph = ch;
	}
	hubs = nh;
	nhubs--;

	hubfail(h); # detach all ports
	devctl(h.dev, "detach");
	closedev(h.dev);
}

portstatus(h: ref Hub, p: int): int { #c!
	sts: int;
	buf := array[4] of byte;

	d := h.dev;
	t := Rd2h|usb->Rclass|usb->Rother;
	if(usbcmd(d, t, usb->GET_STATUS, 0, p, buf, len buf) <0)
		sts = -1;
	else	sts = usb->get2(buf);
	return sts;
}

stsstr(sts: int): string {
	s:= "";
	if(sts&PSsuspend)	s += "z";
	if(sts&PSreset) 	s += "r";
	if(sts&PSslow) 		s += "l";
	if(sts&PShigh) 		s += "h";
	if(sts&PSchange) 	s += "c";
	if(sts&PSenable) 	s += "e";
	if(sts&PSstatuschg) 	s += "s";
	if(sts&PSpresent) 	s += "p";
	if(s =="") 		s = "-";
	return s;
}

getmaxpkt(d: ref Dev, islow: int): int { #c!
	buf := array [64] of byte;
	if(islow)	buf[7] = byte 8;
	else		buf[7] = byte 64;
	if(usbcmd(d
		  ,Rd2h|usb->Rstandard|usb->Rdevice
		  ,usb->GET_DESCRIPTOR, Ddev<<8|0
		  ,0
		  ,buf, len buf) <0)
		return -1;
	#if(int buf[1] != Ddev){
	#	sys->werrstr(sys->sprint("%d is not a dev descriptor", int buf[1]));
	#	return -1;
	#}
	return int buf[7];
}

# bug: does not consider max. power avail.
portattach(h: ref Hub, p, sts: int): ref Dev {
	buf := array[40] of byte;
	nd: ref Dev;
	d := h.dev;
	pp := h.port[p];
	nd = nil;
	pp.state = Pattached;

	Fail: do {
	if(usbdebug)
		sys->fprint(stderr, "usbd: %s: port %d attach sts %#ux\n", d.dir, p, sts);
	sys->sleep(Connectdelay);
	if(hubfeature(h, p, Fportenable, 1) <0)
		sys->fprint(stderr, "usbd: %s: port %d: enable: %r\n", d.dir, p);
	sys->sleep(Enabledelay);
	if(hubfeature(h, p, Fportreset, 1) <0){
		sys->fprint(stderr, "usbd: %s: port %d: reset: %r\n", d.dir, p);
		break Fail;
	}
	sys->sleep(Resetdelay);
	sts = portstatus(h, p);
	if(sts < 0)
		break Fail;
	if((sts & PSenable) == 0){
		sys->fprint(stderr, "usbd: %s: port %d: not enabled?\n", d.dir, p);
		hubfeature(h, p, Fportenable, 1);
		sts = portstatus(h, p);
		if((sts & PSenable) == 0)
			break Fail;
	}
	sp := "full";
	if(sts & PSslow)
		sp = "low";
	if(sts & PShigh)
		sp = "high";
	if(usbdebug)
		sys->fprint(stderr, "usbd: %s: port %d: attached status %#ux\n", d.dir, p, sts);

	if(devctl(d, sys->sprint("newdev %s %d", sp, p)) < 0){
		sys->fprint(stderr, "usbd: %s: port %d: newdev: %r\n", d.dir, p);
		break Fail;
	}
	sys->seek(d.cfd, big 0, 0);
	nr := sys->read(d.cfd, buf, len buf);
	if(nr ==0){ sys->fprint(stderr, "usbd: %s: port %d: newdev: eof\n", d.dir, p); break Fail; }
	if(nr < 0){ sys->fprint(stderr, "usbd: %s: port %d: newdev: %r\n", d.dir, p); break Fail; }
	buf[nr] = byte 0;
	fname := sys->sprint("/dev/usb/%s", string buf);
	nd = opendev(fname);
	if(nd == nil){
		sys->fprint(stderr, "usbd: %s: port %d: opendev: %r\n", d.dir, p);
		break Fail;
	}

	if(usbdebug > 2)
		devctl(nd, "debug 1");

	if(opendevdata(nd, sys->ORDWR) ==nil)
		{ sys->fprint(stderr, "usbd: %s: opendevdata: %r\n", nd.dir); break Fail; }
	if(usbcmd(nd, Rh2d|usb->Rstandard|usb->Rdevice, usb->SET_ADDRESS, nd.id, 0, nil, 0) <0)
		{ sys->fprint(stderr, "usbd: %s: port %d: setaddress: %r\n", nd.dir, p); break Fail; }
	if(devctl(nd, "address") < 0)
		{ sys->fprint(stderr, "usbd: %s: port %d: set address: %r\n", nd.dir, p); break Fail; }

	mp := getmaxpkt(nd, sp=="low");
	if(mp < 0)
		{ sys->fprint(stderr, "usbd: %s: port %d: getmaxpkt: %r\n", nd.dir, p); break Fail; }

	if(usbdebug)
		sys->fprint(stderr, "usbd; %s: port %d: maxpkt %d\n", d.dir, p, mp);
	devctl(nd, sys->sprint("maxpkt %d", mp));

	if((sts & PSslow) != 0 && sp =="full")
		sys->fprint(stderr, "usbd: %s: port %d: %s is full speed when port is low\n", d.dir, p, nd.dir);

	if(configdev(nd) < 0){
		sys->fprint(stderr, "usbd: %s: port %d: configdev: %r\n", d.dir, p);
		break Fail;
	}
	#
	# We always set conf #1. BUG.
	#
	if(usbcmd(nd, Rh2d|usb->Rstandard|usb->Rdevice, Rsetconf, 1, 0, nil, 0) <0){
		sys->fprint(stderr, "usbd: %s: port %d: setconf: %r\n", d.dir, p);
		unstall(nd, nd, Eout);
		if(usbcmd(nd, Rh2d|usb->Rstandard|usb->Rdevice, Rsetconf, 1, 0, nil, 0) < 0)
			break Fail;
	}
	pp.state = Pconfiged;
	if(usbdebug)
		sys->fprint(stderr, "usbd: %s: port %d: configed: %s\n", d.dir, p, nd.dir);
	return pp.dev = nd;

	} while(0);
#Fail:
	pp.state = Pdisabled;
	pp.sts = 0;
	if(pp.hub !=nil)
		pp.hub = nil; # hub closed by enumhub
	hubfeature(h, p, Fportenable, 0);
	if(nd !=nil)
		devctl(nd, "detach");
	closedev(nd);
	return nil;
}

portdetach(h: ref Hub, p: int)
{
#	extern void usbfsgone(char*);
	d := h.dev;
	pp := h.port[p];

	#
	# Clear present, so that we detect an attach on reconnects.
	#
	pp.sts &= ~(PSpresent|PSenable);

	if(pp.state == Pdisabled)
		return;
	pp.state = Pdisabled;
	sys->fprint(stderr, "usbd: %s: port %d: detached\n", d.dir, p);

	if(pp.hub !=nil){
		closehub(pp.hub);
		pp.hub = nil;
	}
	#if(pp.devmaskp !=nil)
	#	putdevnb(pp.devmaskp, pp.devnb);
	#pp.devmaskp = nil;
	if(pp.dev !=nil){
		devctl(pp.dev, "detach");
		#usbfsgone(pp->dev->dir);
		closedev(pp.dev);
		pp.dev = nil;
	}
}

#
# The next two functions are included to
# perform a port reset asked for by someone (usually a driver).
# This must be done while no other device is in using the
# configuration address and with care to keep the old address.
# To keep drivers decoupled from usbd they write the reset request
# to the #u/usb/epN.0/ctl file and then exit.
# This is unfortunate because usbd must now poll twice as much.
#
# An alternative to this reset process would be for the driver to detach
# the device. The next function could see that, issue a port reset, and
# then restart the driver once to see if it's a temporary error.
#
# The real fix would be to use interrupt endpoints for non-root hubs
# (would probably make some hubs fail) and add an events file to
# the kernel to report events to usbd. This is a severe change not
# yet implemented.
#
portresetwanted(h: ref Hub, p: int): int {
	buf := array[5] of byte;
	pp := h.port[p];
	nd := pp.dev;
	if(nd !=nil && nd.cfd !=nil && sys->pread(nd.cfd, buf, 5, big 0) ==5)
		return string buf == "reset";
	else
	return 0;
}

portreset(h: ref Hub, p: int) {
	d := h.dev;
	pp := h.port[p];
	nd := pp.dev;
	Fail: do {
	sys->fprint(stderr, "usbd: %s: port %d: resetting\n", d.dir, p);
	if(hubfeature(h, p, Fportreset, 1) <0){
		sys->fprint(stderr, "usbd: %s: port %d: reset: %r\n", d.dir, p);
		break Fail;
	}
	sys->sleep(Resetdelay);
	sts := portstatus(h, p);
	if(sts <0)
		break Fail;
	if((sts & PSenable) ==0){
		sys->fprint(stderr, "usbd: %s: port %d: not enabled?\n", d.dir, p);
		hubfeature(h, p, Fportenable, 1);
		sts = portstatus(h, p);
		if((sts & PSenable) ==0)
			break Fail;
	}
	nd = pp.dev;
	opendevdata(nd, sys->ORDWR);
	if(usbcmd(nd, Rh2d|usb->Rstandard|usb->Rdevice, Rsetaddress, nd.id, 0, nil, 0) < 0){
		sys->fprint(stderr, "usbd: %s: port %d: setaddress: %r\n", d.dir, p);
		break Fail;
	}
	if(devctl(nd, "address") <0){
		sys->fprint(stderr, "usbd: %s: port %d: set address: %r\n", d.dir, p);
		break Fail;
	}
	if(usbcmd(nd, Rh2d|usb->Rstandard|usb->Rdevice, Rsetconf, 1, 0, nil, 0) <0){
		sys->fprint(stderr, "usbd: %s: port %d: setconf: %r\n", d.dir, p);
		unstall(nd, nd, Eout);
		if(usbcmd(nd, Rh2d|usb->Rstandard|usb->Rdevice, Rsetconf, 1, 0, nil, 0) <0)
			break Fail;
	}
	if(nd.dfd !=nil)
		nd.dfd =nil;
	return;
	} while(0);
#Fail:
	pp.state = Pdisabled;
	pp.sts = 0;
	if(pp.hub != nil)
		pp.hub = nil; # hub closed by enumhub
	hubfeature(h, p, Fportenable, 0);
	if(nd != nil)
		devctl(nd, "detach");
	closedev(nd);
}

portgone(pp: ref Port, sts: int): int {
	if(sts < 0) return 1;
	#
	# If it was enabled and it's not now then it may be reconnect.
	# We pretend it's gone and later we'll see it as attached.
	#
	if((pp.sts & PSenable) !=0 && (sts & PSenable) ==0)
		return 1;
	return (pp.sts & PSpresent) !=0 && (sts & PSpresent) ==0;
}

enumhub(h: ref Hub, p: int): int {
	if(h.failed)
		return 0;
	d := h.dev;
	if(usbdebug > 3)
		sys->fprint(stderr, "usbd: %s: port %d enumhub\n", d.dir, p);

	sts := portstatus(h, p);
	#sys->fprint(stderr, "usbd: port status %d\n", sts);
	if(sts < 0){
		hubfail(h); # avoid delays on detachment
		return -1;
	}
	pp := h.port[p];
	onhubs := nhubs;
	if((sts & PSsuspend) !=0){
		if(hubfeature(h, p, Fportenable, 1) <0)
			sys->fprint(stderr, "usbd: %s: port %d: enable: %r\n", d.dir, p);
		sys->sleep(Enabledelay);
		sts = portstatus(h, p);
		sys->fprint(stderr, "usbd: %s: port %d: resumed (sts %#ux)\n", d.dir, p, sts);
	}
	#sys->fprint(stderr, "sts=%d, pp.sts=%d\n", sts, pp.sts);
	if((pp.sts & PSpresent) ==0 && (sts & PSpresent) !=0){
		if(portattach(h, p, sts) != nil)
			if(startdev(pp) < 0)
				portdetach(h, p);
	}else if(portgone(pp, sts))
		portdetach(h, p);
	else if(portresetwanted(h, p))
		portreset(h, p);
	else if(pp.sts != sts){
		if(usbdebug){
			sys->fprint(stderr, "usbd: %s port %d: sts %s %#x ->", d.dir, p, stsstr(pp.sts), pp.sts);
			sys->fprint(stderr, " %s %#x\n",stsstr(sts), sts);
		}
	}
	pp.sts = sts;
	if(onhubs != nhubs)
		return -1;
	return 0;
}

work(portc: chan of string)
{
	fnm : string;
	while((fnm = <- portc) !=nil) {
		sys->print("usbd: starting: %s\n", fnm);
		h := newhub(fnm, nil);
		if(h ==nil)
			sys->fprint(stderr, "usbd: %s: newhub failed: %r\n", fnm);
	}
	#
	# Enumerate (and acknowledge after first enumeration).
	# Do NOT perform enumeration concurrently for the same
	# controller. new devices attached respond to a default
	# address (0) after reset, thus enumeration has to work
	# one device at a time at least before addresses have been
	# assigned.
	# Do not use hub interrupt endpoint because we
	# have to poll the root hub(s) in any case.
	#

	n := 0;
	again: while(1) {
		j: int;
		n++;
		for(h := hd hubs; h !=nil; h = h.next){
			for(j =1; j<= h.nport; j++){
				if(enumhub(h, j) < 0){
					# changes in hub list; repeat
					continue again;
				}
			}
		}
		if(portc !=nil && n>4){
			portc <- = nil;
			portc = nil;
		}
		sys->sleep(pollms);
		#if(mustdump) dump();
		#break;
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	usbbase = "/dev/usb/";
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	lock = load Lock Lock->PATH;
	lock->init();

	usb = load Usb Usb->PATH;
	usb->init();

	arg = load Arg Arg->PATH;

	stderr = sys->fildes(2);

	hubs = nil;
	verbose = 0;
	usbdebug = 0;

	arg->init(args);
	arg->setusage("usbd [-dv] [-i interface]");
	while ((c := arg->opt()) != 0)
		case c {
		'v' => verbose = 1;
		'd' => usbdebug = 1;
		'i' => usbbase = arg->earg() + "/";
		* => arg->usage();
		}
	args = arg->argv();

	sema = Semaphore.new();

	sys->print("usbd: base: %s\n", usbbase);
	portc := chan of string;
	spawn work(portc);

	fd := sys->open(usbbase, sys->OREAD);
	if(fd == nil) {
		sys->fprint(stderr, "cannot open: %r\n");
	}
	(n, d) := sys->dirread(fd);
	for(i := 0; i < n; i++) {
		if (d[i].name == "ctl") continue;
		portc <- = usbbase+d[i].name;
	}
	portc <- = nil;
	err := <- portc;
}
