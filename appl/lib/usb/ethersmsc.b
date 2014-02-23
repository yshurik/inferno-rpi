implement UsbDriver;

include "sys.m";
	sys: Sys;
include "string.m";
	str: String;
include "usb.m";
	usb: Usb;

include "dhcp.m";
	dhcpclient: Dhcpclient;
	Bootconf: import dhcpclient;

Hdrsize		:con 128;	# plenty of room for headers
Msgsize		:con 8216;	# our preferred iounit (also devmnt's)
Bufsize		:con Hdrsize + Msgsize;

Eaddrlen	:con 6;
Epktlen		:con 1514;
Ehdrsize	:con 2*Eaddrlen + 2;

Maxpkt		:con 2000;	# no jumbo packets here
Nconns		:con 8;		# max number of connections
Nbufs		:con 32;	# max number of buffers
Scether		:con 6;		# ethernet cdc subclass
Fnheader	:con 0;		# Functions
Fnunion		:con 6;
Fnether		:con 15;

Cdcunion	:con 6;

Ether: adt {
	epinid: int;			# epin address
	epoutid: int;			# epout address
	dev: ref Usb->Dev;		# usb ctl
	epin: ref Usb->Dev;		# usb inp
	epout: ref Usb->Dev;		# usb out
	addr: array of byte;		# mac
	init: ref fn(e: ref Ether): (int,int,int);
	bufsize: int;
	name: string;
};
mkether(): ref Ether {
	e := ref Ether;
	e.addr = array[Eaddrlen] of byte;
	return e;
}

argv0: string;
etherdebug: int;

dprint(n: int, s: string)
	{if(etherdebug) sys->fprint(sys->fildes(n), "%s: %s", argv0, s);}
deprint(n: int, s: string)
	{if(etherdebug>1) sys->fprint(sys->fildes(n), "%s: %s", argv0, s);}

# SMSC
Doburst		:con 1;
Resettime	:con 1000;
E2pbusytime	:con 1000;
Afcdefault	:con 16rF830A1;
#Hsburst	:con 37; # from original linux driver
Hsburst		:con 8;
Fsburst		:con 129;
Defbulkdly	:con 16r2000;

Ethp8021q	:con 16r8100;
MACoffset 	:con 1;
PHYinternal	:con 1;
Rxerror		:con 16r8000;
Txfirst		:con 16r2000;
Txlast		:con 16r1000;

# USB vendor requests
Writereg	:con 16rA0;
Readreg		:con 16rA1;

# device registers
Intsts		:con 16r08;
Txcfg		:con 16r10;
	Txon	:con 1<<2;
Hwcfg		:con 16r14;
	Bir	:con 1<<12;
	Rxdoff	:con 3<<9;
	Mef	:con 1<<5;
	Lrst	:con 1<<3;
	Bce	:con 1<<1;
Pmctrl		:con 16r20;
	Phyrst	:con 1<<4;
Ledgpio		:con 16r24;
	Ledspd	:con 1<<24;
	Ledlnk	:con 1<<20;
	Ledfdx	:con 1<<16;
Afccfg		:con 16r2C;
E2pcmd		:con 16r30;
	Busy	:con 1<<31;
	Timeout	:con 1<<10;
	Read	:con 0;
E2pdata		:con 16r34;
Burstcap	:con 16r38;
Intepctl	:con 16r68;
	Phyint	:con 1<<15;
Bulkdelay	:con 16r6C;
Maccr		:con 16r100;
	Mcpas	:con 1<<19;
	Prms	:con 1<<18;
	Hpfilt	:con 1<<13;
	Txen	:con 1<<3;
	Rxen	:con 1<<2;
Addrh		:con 16r104;
Addrl		:con 16r108;
Hashh		:con 16r10C;
Hashl		:con 16r110;
MIIaddr		:con 16r114;
	MIIwrite:con 1<<1;
	MIIread	:con 0<<1;
	MIIbusy	:con 1<<0;
MIIdata		:con 16r118;
Flow		:con 16r11C;
Vlan1		:con 16r120;
Coecr		:con 16r130;
	Txcoe	:con 1<<16;
	Rxcoemd	:con 1<<1;
	Rxcoe	:con 1<<0;

# MII registers
Bmcr		:con 0;
	Bmcrreset:con 1<<15;
	Speed100:con 1<<13;
	Anenable:con 1<<12;
	Anrestart:con 1<<9;
	Fulldpx	:con 1<<8;
Bmsr		:con 1;
Advertise	:con 4;
	Adcsma	:con 16r0001;
	Ad10h	:con 16r0020;
	Ad10f	:con 16r0040;
	Ad100h	:con 16r0080;
	Ad100f	:con 16r0100;
	Adpause	:con 16r0400;
	Adpauseasym:con 16r0800;
	Adall	:con Ad10h|Ad10f|Ad100h|Ad100f;
Phyintsrc	:con 29;
Phyintmask	:con 30;
	Anegcomp:con 1<<6;
	Linkdown:con 1<<4;

wr(d: ref Usb->Dev, reg, val: int): int {
	buf := array[4] of byte;
	usb->put4(buf, val);
	ret := usb->usbcmd(d, Usb->Rh2d|Usb->Rvendor|Usb->Rdev, Writereg, 0, reg,
		buf, 4);
	if(ret < 0)
		deprint(2, sys->sprint("%s: wr(%x, %x): %r", argv0, reg, val));
	return ret;
}

rr(d: ref Usb->Dev, reg: int): int {
	buf := array[4] of byte;
	ret := usb->usbcmd(d, Usb->Rd2h|Usb->Rvendor|Usb->Rdev, Readreg, 0, reg,
		buf, 4);
	if(ret < 0){
		sys->fprint(sys->fildes(2), "%s: rr(%x): %r", argv0, reg);
		return 0;
	}
	return usb->get4(buf);
}

miird(d: ref Usb->Dev, idx: int): int {
	while(rr(d, MIIaddr) & MIIbusy)
		;
	wr(d, MIIaddr, PHYinternal<<11 | idx<<6 | MIIread);
	while(rr(d, MIIaddr) & MIIbusy)
		;
	return rr(d, MIIdata);
}

miiwr(d: ref Usb->Dev, idx, val: int) {
	while(rr(d, MIIaddr) & MIIbusy)
		;
	wr(d, MIIdata, val);
	wr(d, MIIaddr, PHYinternal<<11 | idx<<6 | MIIwrite);
	while(rr(d, MIIaddr) & MIIbusy)
		;
}

eepromr(d: ref Usb->Dev, off: int, buf: array of byte, siz: int): int {
	dprint(2,"smsc, eeprom\n");
	for(i := 0; i < E2pbusytime; i++)
		if((rr(d, E2pcmd) & Busy) == 0)
			break;
	if(i == E2pbusytime)
		return -1;
	for(i = 0; i < siz; i++){
		wr(d, E2pcmd, Busy|Read|(i+off));
		while((v := rr(d, E2pcmd) & (Busy|Timeout)) == Busy)
			;
		if(v & Timeout)
			return -1;
		buf[i] = byte rr(d, E2pdata);
	}
	return 0;
}

phyinit(d: ref Usb->Dev) {
	miiwr(d, Bmcr, Bmcrreset|Anenable);
	for(i := 0; i < Resettime/10; i++){
		if((miird(d, Bmcr) & Bmcrreset) == 0)
			break;
		sys->sleep(10);
	}
	miiwr(d, Advertise, Adcsma|Adall|Adpause|Adpauseasym);
	miird(d, Phyintsrc);
	miiwr(d, Phyintmask, Anegcomp|Linkdown);
	miiwr(d, Bmcr, miird(d, Bmcr)|Anenable|Anrestart);
}


doreset(d: ref Usb->Dev, reg, bit: int): int {
	if(wr(d, reg, bit) < 0)
		return -1;
	for(i := 0; i < Resettime/10; i++){
		 if((rr(d, reg) & bit) == 0)
			return 1;
		sys->sleep(10);
	}
	return 0;
}

getmac(nil: ref Usb->Dev, buf: array of byte): int {
	dprint(2,"smsc: getmac()\n");
	fd := sys->open("/env/ethermac", sys->OREAD);
	if(fd ==nil) return -1;

	s := array[12] of byte;
	nr := sys->read(fd, s, 12);
	if (nr != 12) return -1;

	for(i := 0; i < len s; i++){
		v :=0;
		if(s[i] >= byte 'a' && s[i] <= byte 'f')
			v = 10 + int s[i] - 'a';
		else if(s[i] >= byte '0' && s[i] <= byte '9')
			v = int s[i] - '0';

		if(i%2)
			buf[i/2] += byte v;
		else	buf[i/2] = byte (v*16);
	}
	return Eaddrlen;
}

smscinit(ether: ref Ether): int {
	d := ether.dev;
	dprint(2, "smsc: setting up SMSC95XX\n");
	if(!doreset(d, Hwcfg, Lrst) || !doreset(d, Pmctrl, Phyrst))
		return -1;
	if(getmac(d, ether.addr) < 0)
		return -1;
	wr(d, Addrl, usb->get4(ether.addr));
	wr(d, Addrh, usb->get2(ether.addr[4:]));
	if(Doburst){
		wr(d, Hwcfg, (rr(d,Hwcfg)&~Rxdoff)|Bir|Mef|Bce);
		wr(d, Burstcap, Hsburst);
	}else{
		wr(d, Hwcfg, (rr(d,Hwcfg)&~(Rxdoff|Mef|Bce))|Bir);
		wr(d, Burstcap, 0);
	}
	wr(d, Bulkdelay, Defbulkdly);
	wr(d, Intsts, ~0);
	wr(d, Ledgpio, Ledspd|Ledlnk|Ledfdx);
	wr(d, Flow, 0);
	wr(d, Afccfg, Afcdefault);
	wr(d, Vlan1, Ethp8021q);
	wr(d, Coecr, rr(d,Coecr)&~(Txcoe|Rxcoe)); # TODO could offload checksums?

	wr(d, Hashh, 0);
	wr(d, Hashl, 0);
	wr(d, Maccr, rr(d,Maccr)&~(Prms|Mcpas|Hpfilt));

	phyinit(d);

	wr(d, Intepctl, rr(d, Intepctl)|Phyint);
	wr(d, Maccr, rr(d, Maccr)|Txen|Rxen);
	wr(d, Txcfg, Txon);

	return 0;
}

smscreset(e: ref Ether): int {
	dev := e.dev;
	if(dev.usb.vid != 16r0424 || dev.usb.did != 16rec00) {
		deprint(2, "smsc: not fit usb vid/did\n");
		return -1;
	}

	if(smscinit(e) < 0){
		deprint(2, "smsc: smsc init failed: %r\n");
		return -1;
	}
	deprint(2, "smsc: smsc reset done\n");
	e.name = "smsc";
	if(Doburst)	e.bufsize = Hsburst*512;
	else		e.bufsize = Maxpkt;
	return 0;
}

# ether part of driver

setalt(d: ref Usb->Dev, ifcid, altid: int) {
	if(usb->usbcmd(d, usb->Rh2d|usb->Rstd|usb->Riface, usb->Rsetiface, altid, ifcid, nil, 0) < 0)
		dprint(2, sys->sprint("%s: setalt ifc %d alt %d: %r\n", argv0, ifcid, altid));
}

ifaceinit(e: ref Ether, ifc: ref Usb->Iface): (int,int,int) {
	epin := -1;
	epout := -1;

	if(ifc == nil)
		return (-1,epin,epout);

	for(i := 0; (epin < 0 || epout < 0) && i < len(ifc.ep); i++)
		if((ep := ifc.ep[i]) != nil && ep.typ == usb->Ebulk){
			if(ep.dir == usb->Eboth || ep.dir == usb->Ein)
				if(epin == -1)
					epin =  ep.id;
			if(ep.dir == usb->Eboth || ep.dir == usb->Eout)
				if(epout == -1)
					epout = ep.id;
		}
	if(epin == -1 || epout == -1)
		return (-1,epin,epout);

	dprint(2, sys->sprint("ether: ep ids: in %d out %d\n", epin, epout));
	for(i = 0; i < len(ifc.altc); i++)
		if(ifc.altc[i] != nil)
			setalt(e.dev, ifc.id, i);

	return (0,epin,epout);
}

etherinit(e: ref Ether): (int,int,int) {
	ei := -1;
	eo := -1;
	ud := e.dev.usb;

	# look for union descriptor with ethernet ctrl interface
	for(i := 0; i < len(ud.ddesc); i++){
		if((desc := ud.ddesc[i]) == nil)
			continue;
		if(int desc.data[0] < 5 || int desc.data[2+0] != Cdcunion)
			continue;

		ctlid := int desc.data[2+1];
		datid := int desc.data[2+2];

		if((c := desc.conf) == nil)
			continue;

		ctlif,datif: ref Usb->Iface;
		ctlif = nil;
		datif = nil;
		for(j := 0; j < len(c.iface); j++){
			if(c.iface[j] == nil)
				continue;
			if(c.iface[j].id == ctlid)
				ctlif = c.iface[j];
			if(c.iface[j].id == datid)
				datif = c.iface[j];

			if(datif != nil && ctlif != nil){
				if(usb->Subclass(ctlif.csp) == Scether) {
					r: int;
					(r, ei,eo) = ifaceinit(e, datif);
					if (r != -1)
						return (0,ei,eo);
				}
				break;
			}
		}
	}
	# try any other one that seems to be ok
	for(i = 0; i < len(ud.conf); i++)
		if((c := ud.conf[i]) != nil)
			for(j := 0; j < len(c.iface); j++) {
				r: int;
				(r, ei,eo) = ifaceinit(e, c.iface[j]);
				if(r != -1)
					return (0,ei,eo);
			}
	dprint(2, sys->sprint("%s: no valid endpoints", argv0));
	return (-1,ei,eo);
}

openeps(e: ref Ether, epin, epout: int): int {
	e.epin = usb->openep(e.dev, epin);
	if(e.epin == nil){
		sys->fprint(sys->fildes(2), "ether: in: openep %d: %r\n", epin);
		return -1;
	}
	if(epout == epin){
		e.epout = e.epin;
	}else
		e.epout = usb->openep(e.dev, epout);
	if(e.epout == nil){
		sys->fprint(sys->fildes(2), "ether: out: openep %d: %r\n", epout);
		usb->closedev(e.epin);
		return -1;
	}
	if(e.epin == e.epout)
		usb->opendevdata(e.epin, sys->ORDWR);
	else{
		usb->opendevdata(e.epin, sys->OREAD);
		usb->opendevdata(e.epout, sys->OWRITE);
	}
	if(e.epin.dfd ==nil || e.epout.dfd ==nil){
		sys->fprint(sys->fildes(2), "ether: open i/o ep data: %r\n");
		usb->closedev(e.epin);
		usb->closedev(e.epout);
		return -1;
	}
	dprint(2, sys->sprint("ether: ep in %s maxpkt %d; ep out %s maxpkt %d\n",
				e.epin.dir, e.epin.maxpkt, e.epout.dir, e.epout.maxpkt));

	# time outs are not activated for I/O endpoints

	if(usb->usbdebug > 2 || etherdebug > 2){
		usb->devctl(e.epin, "debug 1");
		usb->devctl(e.epout, "debug 1");
		usb->devctl(e.dev, "debug 1");
	}

	return 0;
}

seprintaddr(addr: array of byte): string {
	s := "";
	for(i := 0; i < Eaddrlen; i++)
		s += sys->sprint("%02x", int addr[i]);
	return s;
}

kernelproxy(e: ref Ether): int {
	ctlfd := sys->open("#l0/ether0/clone", sys->ORDWR);
	if(ctlfd ==nil){
		deprint(2, sys->sprint("%s: etherusb bind #l0: %r\n", argv0));
		return -1;
	}
	e.epin.dfd =nil;
	e.epout.dfd =nil;
	eaddr := seprintaddr(e.addr);
	n := sys->fprint(ctlfd, "bind %s #u/usb/ep%d.%d/data #u/usb/ep%d.%d/data %s %d %d",
		e.name, e.dev.id, e.epin.id, e.dev.id, e.epout.id,
		eaddr, e.bufsize, e.epout.maxpkt);
	if(n < 0){
		deprint(2, sys->sprint("%s: etherusb bind #l0: %r\n", argv0));
		usb->opendevdata(e.epin, sys->OREAD);
		usb->opendevdata(e.epout, sys->OWRITE);
		ctlfd =nil;
		return -1;
	}
	ctlfd =nil;
	return 0;
}

# default initialization:
# let's get ip with dhcp
confether() {
	fd: ref Sys->FD;
	ethername := "ether0";

	fd = sys->open("/net/ipifc/clone", sys->OWRITE);
	if(fd == nil) {
		sys->print("init: open /net/ipifc/clone: %r\n");
		return;
	}
	if(sys->fprint(fd, "bind ether %s", ethername) < 0) {
		sys->print("could not bind ether0 interface: %r\n");
		return;
	}

	fd = sys->open("/net/ipifc/0/ctl", Sys->OWRITE);
	if(fd == nil){
		sys->print("init: can't reopen /net/ipifc/0/ctl: %r\n");
		return;
	}

	dhcpclient = load Dhcpclient Dhcpclient->PATH;
	if(dhcpclient == nil){
		sys->print("can't load dhcpclient: %r\n");
		return;
	}
	dhcpclient->init();
	(nil, nil, err) := dhcpclient->dhcp("/net", fd, "/net/ether0/addr", nil, nil);
	if(err != nil){
		sys->print("dhcp: %s\n", err);
		return;
	}
}

init(u: Usb, dev: ref Usb->Dev): int {
	usb = u;
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	etherdebug = 0;

	argv0 = "ether";
	ea := array[Eaddrlen] of byte;

	e := mkether();
	e.dev = dev;
	for(j:=0; j<Eaddrlen; j++)
		e.addr[j]=ea[j];
	e.name = "smsc";
	smscreset(e);

	e.init = etherinit;

	r,epin,epout: int;
	(r,epin,epout) = e.init(e);
	if(r <0) return -1;

	if(openeps(e, epin, epout) < 0)
		return -1;

	if(kernelproxy(e) < 0) {
		sys->print("%s: kernelproxy fail.\n", argv0);
		return -1;
	}

	spawn confether();
	return 0;
}

shutdown() {
}
