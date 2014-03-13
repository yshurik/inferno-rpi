#
# Copyright © 2002 Vita Nuova Holdings Limited
#
implement Usb;

include "sys.m";
	sys: Sys;

include "usb.m";

include "string.m";
	str: String;

dprint(s: string)
	{if(usbdebug) sys->fprint(sys->fildes(2), "%s: %s", argv0, s);}
ddprint(s: string)
	{if(usbdebug>1) sys->fprint(sys->fildes(2), "%s: %s", argv0, s);}

mkhub(): ref Hub { h := ref Hub(0,0,0,0,0,0,0,nil,0,0,nil,nil); return h; }
mkport(): ref Port { p := ref Port(0,0,0,0,nil,nil,0); return p; }
mkusbdev(): ref Usbdev {
	u := ref Usbdev;
	u.ep = array[Nep] of ref Ep;
	u.conf = array[Nconf] of ref Conf;
	u.ddesc = array[Nddesc] of ref Desc;
	u.csp = u.vid = u.did = u.dno = u.vsid = u.psid = u.class = u.subclass = u.proto = u.nconf = 0;
	return u;
}
mkep(d: ref Usbdev, id: int): ref Ep {
	ep := ref Ep; ep.id = id;
	d.ep[id] = ep;
	return ep;
}

devnameid(s: string): int { # epN.M -> N
	l,n: string; i: int;
	(l,nil) = str->splitstrl(s,".");
	if (l ==s) return -1;
	(nil,n) = str->splitstrr(l,"p");
	if (n ==s) return -1;
	(i,nil) = str->toint(n,10);
	return i;
}

#stderr = sys->fildes(2);

openep(d: ref Dev, id: int): ref Dev
{
	if(d.cfd == nil || d.usb == nil){
		sys->werrstr("device not configured");
		return nil;
	}
	ud := d.usb;
	if(id < 0 || id >= len ud.ep || ud.ep[id] == nil) {
		sys->werrstr("bad enpoint number");
		return nil;
	}
	ep := ud.ep[id];
	mode := "rw";
	if(ep.dir == Ein)
		mode = "r";
	if(ep.dir == Eout)
		mode = "w";
	name := sys->sprint("/dev/usb/ep%d.%d", d.id, id);
	if(devctl(d, sys->sprint("new %d %d %s", id, ep.typ, mode)) < 0){
		dprint(sys->sprint("%s: new: %r\n", d.dir));
		return nil;
	}
	epd := opendev(name);
	if(epd == nil)
		return nil;
	epd.id = id;
	if(devctl(epd, sys->sprint("maxpkt %d", ep.maxpkt)) < 0)
		sys->fprint(sys->fildes(2), "%s: %s: openep: maxpkt: %r\n", argv0, epd.dir);
	else
		dprint(sys->sprint("%s: maxpkt %d\n", epd.dir, ep.maxpkt));
	epd.maxpkt = ep.maxpkt;
	ac := ep.iface.altc[0];
	if(ep.ntds > 1 && devctl(epd, sys->sprint("ntds %d", ep.ntds)) < 0)
		sys->fprint(sys->fildes(2), "%s: %s: openep: ntds: %r\n", argv0, epd.dir);
	else
		dprint(sys->sprint("%s: ntds %d\n", epd.dir, ep.ntds));

	#
	# For iso endpoints and high speed interrupt endpoints the pollival is
	# actually 2ⁿ and not n.
	# The kernel usb driver must take that into account.
	# It's simpler this way.
	#

	if(ac != nil && (ep.typ == Eintr || ep.typ == Eiso) && ac.interval != 0)
		if(devctl(epd, sys->sprint("pollival %d", ac.interval)) < 0)
			sys->fprint(sys->fildes(2), "%s: %s: openep: pollival: %r\n",
				argv0, epd.dir);
	return epd;
}

opendev(fnm: string): ref Dev {
	d := ref Dev;
	d.dfd = nil;
	d.dir = fnm;;
	d.cfd = sys->open(d.dir+"/ctl", sys->ORDWR);
	d.id = devnameid(fnm);
	if(d.cfd == nil){
		sys->fprint(sys->fildes(2), "usb: can't open endpoint %s: %r", d.dir);
		return nil;
	}
	return d;
}
opendevdata(d: ref Dev, mode: int): ref Sys->FD {
	d.dfd = sys->open(d.dir+"/data", mode);
	return d.dfd;
}
devctl(d: ref Dev, s: string):int {
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
	put2(buf[2:], value);
	put2(buf[4:], index);
	put2(buf[6:], count);
	if (additional)
		buf[8:] = outbuf;

	rv := sys->write(d.dfd, buf, len buf);
	if (rv < 0) return -1;
	if (rv != len buf) return -1;
	return rv;
}
cmdrep(d: ref Dev, buf: array of byte, nb: int): int {
	nb = sys->read(d.dfd, buf, nb);
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
		sys->werrstr(sys->sprint("usb: usbcmd: %s: required %d attempts (%s)\n", d.dir, i, err));
	return r;
}

unstall(dev: ref Dev, ep: ref Dev, dir: int): int {
	if(dir == Ein)
		dir = 16r80;
	else	dir = 0;
	r := Rh2d|Rstd|Rep;
	if(usbcmd(dev, r, Rclearfeature, Fhalt, ep.id|dir, nil, 0)<0){
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
	ddprint(sys->sprint("usb: %s: parsedev: %s\n", xd.dir, hex(b)));

	if(bLen < Ddevlen){
		sys->werrstr(sys->sprint("short dev descr. (%d < %d)", bLen, Ddevlen));
		return -1;
	}
	if(bTyp != Ddev){
		sys->werrstr(sys->sprint("%d is not a dev descriptor", bTyp));
		return -1;
	}
	d.csp = ((int b[4]) | (int b[5])<<8 | (int b[6])<<16);
	d.ep[0].maxpkt = xd.maxpkt = int b[7];
	d.class = int b[4];
	d.subclass = int b[5];
	d.proto = int b[6];
	d.nconf = int b[17];
	if(d.nconf ==0)
		sys->werrstr(sys->sprint("usb: %s: no configurations\n", xd.dir));
	d.vid = get2(b[8:]);
	d.did = get2(b[10:]);
	d.dno = get2(b[12:]);
	d.vsid = int b[14];
	d.psid = int b[15];
	d.ssid = int b[16];
	if(n > Ddevlen)
		ddprint(sys->sprint("usb: %s: parsedev: %d bytes left\n", xd.dir, n-Ddevlen));
	return Ddevlen;
}

loaddevstr(d: ref Dev, sid: int): string {
	langid := 0;
	buf := array[128] of byte;
	if(sid ==0) return "none";
	typ := Rd2h|Rstd|Rdev;
	nr := usbcmd(d, typ, Rgetdesc, Dstr<<8|sid, 0, buf, len buf);
	if(nr < 4)
		langid = 16r0409; # english
	else
		langid = int buf[3]<<8 | int buf[2];
	nr = usbcmd(d, typ, Rgetdesc, Dstr<<8|sid, langid, buf, len buf);
	s := "";
	for(i:=2; i<nr; i +=2) s += sys->sprint("%c", get2(buf[i:i+2]));
	return s;
}
loaddevdesc(d: ref Dev): int {
	nr := 0;
	buf := array[Ddevlen] of byte;
	typ := Rd2h|Rstd|Rdev;
	memset(buf, 0);
	if((nr = usbcmd(d, typ, Rgetdesc, Ddev<<8|0, 0, buf, Ddevlen)) <0)
		return -1;
	if(nr < Ddevlen){
		sys->werrstr(sys->sprint("short device descriptor (%d bytes)", nr));
		return -1;
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
	else
		sys->fprint(sys->fildes(2), "usb: desc error: %r");
	return nr;
}

dname(dtype: int): string {
	case dtype {
	Ddev		=> return "device";
	Dconf		=> return "config";
	Dstr		=> return "string";
	Diface		=> return "interface";
	Dep		=> return "endpoint";
	Dreport		=> return "report";
	Dphysical	=> return "phys";
	}
	return "desc";
}

parseiface(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): (int, ref Iface, ref Altc) {
	class, subclass, proto: int;
	ifid, altid: int;
	ip: ref Iface;
	b = b[:n];
	ddprint(sys->sprint("usb: parseiface  %s\n", hex(b)));

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
	if(d.class == 0) d.class = class;
	if(d.subclass == 0) d.subclass = subclass;
	if(d.proto == 0) d.proto = proto;
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

parseendpt(d: ref Usbdev, nil: ref Conf, ip: ref Iface, altc: ref Altc, b: array of byte, n: int): (int, ref Ep) {
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
	ep.maxpkt = get2(b[4:]);
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
		sys->fprint(sys->fildes(2), "usb: %r\n");
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
	ddprint(sys->sprint("usb: parsedesc  %s\n", hex(b)));

	for(nd :=0; nd < len d.ddesc; nd++)
		if(d.ddesc[nd] ==nil)
			break;

	while(n >2 && int b[0] !=0 && int b[0] <=n){
		blen := int b[0];
		ddprint(sys->sprint("usb: parsedesc %s %x[%d] %s\n",
			dname(int b[1]), int b[1], int b[0], hex(b[:blen])));
		case int b[1] {
		Ddev => ;
		Dconf =>
			sys->werrstr(sys->sprint("unexpected descriptor %d", int b[1]));
			sys->fprint(sys->fildes(2), "usb: parsedesc: %r");
			break;
		Diface =>
			pin: int;
			(pin, ip, altc) = parseiface(d, c, b, n);
			if(pin <0){
				sys->fprint(sys->fildes(2), "usb: parsedesc: %r\n");
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
				sys->fprint(sys->fildes(2), "usb: parsedesc: %r\n");
				return -1;
			}
			break;
		* =>
			if(nd == len d.ddesc){
				sys->fprint(sys->fildes(2)
					,"usb: parsedesc: too many device-specific descriptors for device %s %s\n"
					,d.vendor, d.product);
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
	ddprint(sys->sprint("usb: parseconf  %s\n", hex(b)));

	if(int b[0] < Dconflen){
		sys->werrstr("short configuration descriptor");
		return -1;
	}
	if(int b[1] != Dconf){
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
	l := get2(b[2:]);
	if(n < l){
		sys->werrstr("truncated configuration info");
		return -1;
	}
	n -= Dconflen;
	bdesc := b[Dconflen:];
	nr := 0;
	if(n >0 && (nr=parsedesc(d, c, bdesc, n)) <0)
		return -1;
	n -= nr;
	if(n > 0)
		ddprint(sys->sprint("usb: parseconf: %d bytes left\n", n));
	return l;
}

loaddevconf(d: ref Dev, n: int): int {
	if(n >= len d.usb.conf){
		sys->werrstr("loaddevconf: bug: out of configurations in device");
		sys->fprint(sys->fildes(2), "usb: %r\n");
		return -1;
	}
	buf := array[Dconflen] of byte;
	typ := Rd2h|Rstd|Rdev;
	nr := usbcmd(d, typ, Rgetdesc, Dconf<<8|n, 0, buf, Dconflen);
	if(nr != Dconflen)
		return -1;

	buf_len := get2(buf[2:]);
	buf = array[buf_len] of byte;

	nr = usbcmd(d, typ, Rgetdesc, Dconf<<8|n, 0, buf, buf_len);
	if(nr != buf_len)
		return -1;

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
	for(i :=0; i < d.usb.nconf && i < Nconf; i++)
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
	s := sys->sprint("info %s csp %#08dux", classname(ud.class), ud.csp);
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
				s += sys->sprint(" csp %#08dux", ifc.csp);
		}
	}
	s += sys->sprint(" vid %06#x did %06#x", ud.vid, ud.did);
	s += sys->sprint(" %s %s", ud.vendor, ud.product);
	devctl(d, s);
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
	d.cfd = d.dfd = nil;
	ud := d.usb;
	d.usb =nil;
	if(ud !=nil){
		for(i :=0; i < len ud.conf; ++i)
			closeconf(ud.conf[i]);
	}
	d =nil;
}

getmaxpkt(d: ref Dev, islow: int): int { #c!
	buf := array [64] of byte;
	if(islow)	buf[7] = byte 8;
	else		buf[7] = byte 64;
	if(usbcmd(d
		  ,Rd2h|Rstd|Rdev
		  ,Rgetdesc, Ddev<<8|0
		  ,0
		  ,buf, len buf) <0)
		return -1;
	if(int buf[1] != Ddev){
		sys->werrstr(sys->sprint("%d is not a dev descriptor", int buf[1]));
		return -1;
	}
	return int buf[7];
}

get2(b: array of byte): int
{
	return int b[0] | (int b[1] << 8);
}

put2(buf: array of byte, v: int)
{
	buf[0] = byte v;
	buf[1] = byte (v >> 8);
}

get4(b: array of byte): int
{
	return int b[0] | (int b[1] << 8) | (int b[2] << 16) | (int b[3] << 24);
}

put4(buf: array of byte, v: int)
{
	buf[0] = byte v;
	buf[1] = byte (v >> 8);
	buf[2] = byte (v >> 16);
	buf[3] = byte (v >> 24);
}

bigget2(b: array of byte): int
{
	return int b[1] | (int b[0] << 8);
}

bigput2(buf: array of byte, v: int)
{
	buf[1] = byte v;
	buf[0] = byte (v >> 8);
}

bigget4(b: array of byte): int
{
	return int b[3] | (int b[2] << 8) | (int b[1] << 16) | (int b[0] << 24);
}

bigput4(buf: array of byte, v: int)
{
	buf[3] = byte v;
	buf[2] = byte (v >> 8);
	buf[1] = byte (v >> 16);
	buf[0] = byte (v >> 24);
}

strtol(s: string, base: int): (int, string)
{
	if (str == nil)
		str = load String String->PATH;
	if (base != 0)
		return str->toint(s, base);
	if (len s >= 2 && (s[0:2] == "0X" || s[0:2] == "0x"))
		return str->toint(s[2:], 16);
	if (len s > 0 && s[0:1] == "0")
		return str->toint(s[1:], 8);
	return str->toint(s, 10);
}

memset(buf: array of byte, v: int)
{
	for (x := 0; x < len buf; x++)
		buf[x] = byte v;
}

Class(csp:int): int {return (csp) & 16rff;}
Subclass(csp:int): int {return ((csp)>>8) & 16rff;}
Proto(csp:int): int {return ((csp)>>16) & 16rff;}
CSP(c,s,p:int): int {return (c) | (s)<<8 | (p)<<16;}

init() {
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
}
