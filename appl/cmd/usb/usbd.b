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
	Nep, Nconf,Nddesc,Uctries,Ucdelay,Naltc,Niface: import usb;
	pollms: import usb;
	Rd2h,Rh2d: import usb;
	Fportpower,Fportindicator,Fportenable,Fportreset: import usb;
	PSsuspend,PSreset,PSslow,PShigh,PSenable,PSpresent,PSchange,PSstatuschg: import usb;
	Spawndelay,Powerdelay,Connectdelay,Enabledelay,Resetdelay: import usb;
	Pattached,Pconfiged,Pdisabled: import usb;
	Rgetdesc,Rsetconf,Rsetaddress: import usb;
	Clhub: import usb;
	Difacelen,Dhublen,Deplen: import usb;
	Dep,Ddev,Dhub,Diface: import usb;
	Fhalt: import usb;
	Ein,Eout,Eboth,Econtrol: import usb;
	Ep,Dev,Hub,Port,Conf,Desc,Altc,Iface,Usbdev: import usb;
	mkep,mkhub,mkport,mkusbdev: import usb;
	hex: import usb;
	usbcmd: import usb;
	usbdebug: import usb;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Usbd: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

usbbase: string;
verbose: int;
stderr: ref Sys->FD;

########################### dev part ##########################

startdev(pp: ref Port): int {
	d := pp.dev;
	ud := d.usb;

	usb->writeinfo(d);
	if(ud.vendor =="none") {
		ud.vendor = searchdbkey(ud,"vname");
		ud.product = searchdbkey(ud,"pname");
	}

	#sys->fprint(stderr,"usb:%02x:%02x:%02x/%04x:%04x:%s:%s %s\n"
	#	,ud.class, ud.subclass,ud.proto, ud.vid, ud.did, d.dir
	#	,ud.vendor,ud.product);

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
		if(usbdebug > 1)
			usb->devctl(d, "debug 0"); # polled hubs are chatty
		if(pp.hub ==nil) return -1;
		return 0;
	}
	else if (ud.nconf >= 1 && ud.class !=0 && (path := searchdriverdatabase(ud, ud.conf[0])) != nil) {
		pp.dev.mod = load UsbDriver path;
		if (pp.dev.mod == nil)
			sys->fprint(stderr, "usbd: failed to load %s\n", path);
		else {
			rv := pp.dev.mod->init(usb, pp.dev);
			if (rv == -11) {
				sys->fprint(stderr, "usbd: %s: reenumerate\n", path);
				pp.dev.mod = nil;
				#reenumerate = 1;
			}
			else if (rv < 0) {
				sys->fprint(stderr, "usbd: %s:init failed\n", path);
				pp.dev.mod = nil;
			}
			else if (verbose)
				sys->fprint(stderr, "%s running\n", path);
		}
	}

	sys->sleep(Spawndelay); # in case we re-spawn too fast
	return 0;
}

########################### end: dev part ##########################

hubfeature(h: ref Hub, port, f, on: int): int {
	cmd: int;
	if(on)	cmd = usb->Rsetfeature;
	else	cmd = usb->Rclearfeature;
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
	typ := Rd2h|usb->Rclass|usb->Rdev;
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
			h.dev = usb->opendev(fnm);
			if(h.dev ==nil){
				sys->fprint(stderr, "usbd: opendev: %s: %r", fnm);
				break fail;
			}
			if(usb->opendevdata(h.dev, sys->ORDWR) ==nil){
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
		usb->devctl(h.dev, "hub");
		ud := h.dev.usb;
		if(h.isroot)
			usb->devctl(h.dev, sys->sprint("info roothub csp %#08ux ports %d", 16r000009, h.nport));
		else {
			#devctl(h.dev, sys->sprint("info hub csp %#08ulx ports %d %q %q",
			usb->devctl(h.dev, sys->sprint("info hub csp %#08ux ports %d %s %s",
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
	if(d !=nil) usb->devctl(d, "detach");
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
	usb->devctl(h.dev, "detach");
	usb->closedev(h.dev);
}

portstatus(h: ref Hub, p: int): int { #c!
	sts: int;
	buf := array[4] of byte;

	d := h.dev;
	t := Rd2h|usb->Rclass|usb->Rother;
	if(usbcmd(d, t, usb->Rgetstatus, 0, p, buf, len buf) <0)
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
		sys->fprint(stderr, "usbd: %s: port %d: attach sts %#ux\n", d.dir, p, sts);
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

	if(usb->devctl(d, sys->sprint("newdev %s %d", sp, p)) < 0){
		sys->fprint(stderr, "usbd: %s: port %d: newdev: %r\n", d.dir, p);
		break Fail;
	}
	sys->seek(d.cfd, big 0, 0);
	nr := sys->read(d.cfd, buf, len buf);
	if(nr ==0){ sys->fprint(stderr, "usbd: %s: port %d: newdev: eof\n", d.dir, p); break Fail; }
	if(nr < 0){ sys->fprint(stderr, "usbd: %s: port %d: newdev: %r\n", d.dir, p); break Fail; }
	buf[nr] = byte 0;
	fname := sys->sprint("/dev/usb/%s", string buf);
	nd = usb->opendev(fname);
	if(nd == nil){
		sys->fprint(stderr, "usbd: %s: port %d: opendev: %r\n", d.dir, p);
		break Fail;
	}

	if(usbdebug > 2)
		usb->devctl(nd, "debug 1");

	if(usb->opendevdata(nd, sys->ORDWR) ==nil)
		{ sys->fprint(stderr, "usbd: %s: opendevdata: %r\n", nd.dir); break Fail; }
	if(usbcmd(nd, Rh2d|usb->Rstd|usb->Rdev, usb->Rsetaddress, nd.id, 0, nil, 0) <0)
		{ sys->fprint(stderr, "usbd: %s: port %d: setaddress: %r\n", nd.dir, p); break Fail; }
	if(usb->devctl(nd, "address") < 0)
		{ sys->fprint(stderr, "usbd: %s: port %d: set address: %r\n", nd.dir, p); break Fail; }

	mp := usb->getmaxpkt(nd, sp=="low");
	if(mp < 0)
		{ sys->fprint(stderr, "usbd: %s: port %d: getmaxpkt: %r\n", nd.dir, p); break Fail; }

	if(usbdebug)
		sys->fprint(stderr, "usbd: %s: port %d: maxpkt %d\n", d.dir, p, mp);
	usb->devctl(nd, sys->sprint("maxpkt %d", mp));

	if((sts & PSslow) != 0 && sp =="full")
		sys->fprint(stderr, "usbd: %s: port %d: %s is full speed when port is low\n", d.dir, p, nd.dir);

	if(usb->configdev(nd) < 0){
		sys->fprint(stderr, "usbd: %s: port %d: configdev: %r\n", d.dir, p);
		break Fail;
	}
	#
	# We always set conf #1. BUG.
	#
	if(usbcmd(nd, Rh2d|usb->Rstd|usb->Rdev, Rsetconf, 1, 0, nil, 0) <0){
		sys->fprint(stderr, "usbd: %s: port %d: setconf: %r\n", d.dir, p);
		usb->unstall(nd, nd, Eout);
		if(usbcmd(nd, Rh2d|usb->Rstd|usb->Rdev, Rsetconf, 1, 0, nil, 0) < 0)
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
		usb->devctl(nd, "detach");
	usb->closedev(nd);
	return nil;
}

portdetach(h: ref Hub, p: int)
{
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
		usb->devctl(pp.dev, "detach");
		#usbfsgone(pp->dev->dir);
		usb->closedev(pp.dev);
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
	usb->opendevdata(nd, sys->ORDWR);
	if(usbcmd(nd, Rh2d|usb->Rstd|usb->Rdev, Rsetaddress, nd.id, 0, nil, 0) < 0){
		sys->fprint(stderr, "usbd: %s: port %d: setaddress: %r\n", d.dir, p);
		break Fail;
	}
	if(usb->devctl(nd, "address") <0){
		sys->fprint(stderr, "usbd: %s: port %d: set address: %r\n", d.dir, p);
		break Fail;
	}
	if(usbcmd(nd, Rh2d|usb->Rstd|usb->Rdev, Rsetconf, 1, 0, nil, 0) <0){
		sys->fprint(stderr, "usbd: %s: port %d: setconf: %r\n", d.dir, p);
		usb->unstall(nd, nd, Eout);
		if(usbcmd(nd, Rh2d|usb->Rstd|usb->Rdev, Rsetconf, 1, 0, nil, 0) <0)
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
		usb->devctl(nd, "detach");
	usb->closedev(nd);
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
	}else if(portgone(pp, sts)) {
		if(pp.dev != nil && pp.dev.mod != nil && pp.dev.mod->shutdown != nil)
			pp.dev.mod->shutdown();
		portdetach(h, p);
	}else if(portresetwanted(h, p))
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
		#sys->print("usbd: starting: %s\n", fnm);
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

Line: adt {
	level: int;
	command: string;
	value: int;
	svalue: string;
};

lines: array of Line;

searchdbkey(d: ref Usbdev, key: string): string {
	back := 0;
	level := 0;
	for (i := 0; i < len lines; i++) {
		if (back) {
			if (lines[i].level > level)
				continue;
			back = 0;
		}
		if (lines[i].level != level) {
			level = 0;
			back = 1;
		}

		if (lines[i].command ==key)
			return lines[i].svalue;

		case lines[i].command {
		"class" =>
			if (d.class != 0) {
				if (lines[i].value != d.class)
					back = 1;
			}
		"subclass" =>
			if (d.class != 0) {
				if (lines[i].value != d.subclass)
					back = 1;
			}
		"proto" =>
			if (d.class != 0) {
				if (lines[i].value != d.proto)
					back = 1;
			}
		"vendor" =>
			if (lines[i].value != d.vid)
				back =1;
		"product" =>
			if (lines[i].value != d.did)
				back =1;
		* =>
			continue;
		}
		if (!back)
			level++;
	}
	return "none";
}

searchdriverdatabase(d: ref Usbdev, nil: ref Conf): string {
	back := 0;
	level := 0;
	for (i := 0; i < len lines; i++) {
		if (verbose > 1)
			sys->fprint(stderr, "search line %d: lvl %d cmd %s val %d (back %d lvl %d)\n",
				i, lines[i].level, lines[i].command, lines[i].value, back, level);
		if (back) {
			if (lines[i].level > level)
				continue;
			back = 0;
		}
		if (lines[i].level != level) {
			level = 0;
			back = 1;
		}
		case lines[i].command {
		"class" =>
			if (d.class != 0) {
				if (lines[i].value != d.class)
					back = 1;
			}
			#else if (lines[i].value != (hd conf.iface[0].altiface).class)
			#	back = 1;
		"subclass" =>
			if (d.class != 0) {
				if (lines[i].value != d.subclass)
					back = 1;
			}
			#else if (lines[i].value != (hd conf.iface[0].altiface).subclass)
			#	back = 1;
		"proto" =>
			if (d.class != 0) {
				if (lines[i].value != d.proto)
					back = 1;
			}
			#else if (lines[i].value != (hd conf.iface[0].altiface).proto)
			#	back = 1;
		"vendor" =>
			if (lines[i].value != d.vid)
				back =1;
		"product" =>
			if (lines[i].value != d.did)
				back =1;
		"load" =>
			return lines[i].svalue;
		* =>
			continue;
		}
		if (!back)
			level++;
	}
	return nil;
}

loaddriverdatabase()
{
	newlines: array of Line;

	if (bufio == nil)
		bufio = load Bufio Bufio->PATH;

	iob := bufio->open(Usb->DATABASEPATH, Sys->OREAD);
	if (iob == nil) {
		sys->fprint(stderr, "usbd: couldn't open %s: %r\n", Usb->DATABASEPATH);
		return;
	}
	lines = array[100] of Line;
	lc := 0;
	while ((line := iob.gets('\n')) != nil) {
		if (line[0] == '#')
			continue;
		level := 0;
		while (line[0] == '\t') {
			level++;
			line = line[1:];
		}
		(n, l) := sys->tokenize(line[0: len line - 1], "\t ");
		if (n != 2)
			continue;
		if (lc >= len lines) {
			newlines = array [len lines * 2] of Line;
			newlines[0:] = lines[0: len lines];
			lines = newlines;
		}
		lines[lc].level = level;
		lines[lc].command = hd l;
		case hd l {
		"class" or "subclass" or "proto" or "vendor" or "product" =>
			(lines[lc].value, nil) = usb->strtol(hd tl l, 0);
		"load" =>
			lines[lc].svalue = hd tl l;
		"vname" =>
			lines[lc].svalue = hd tl l;
		"pname" =>
			lines[lc].svalue = hd tl l;
		* =>
			continue;
		}
		lc++;
	}
	if (verbose)
		sys->fprint(stderr, "usbd: loaded %d lines\n", lc);
	newlines = array [lc] of Line;
	newlines[0:] = lines[0 : lc];
	lines = newlines;
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

	loaddriverdatabase();

	#sys->print("usbd: base: %s\n", usbbase);
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
	if(err != nil)
		sys->print("usbd: err: %s\n", err);
}
