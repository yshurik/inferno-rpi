implement UsbDriver;

include "sys.m";
	sys: Sys;
	open,read,write,pctl,fprint,sprint,fildes: import sys;
include "string.m";
	str: String;
include "usb.m";
	usb: Usb;
	dprint,usbdebug: import usb;
	usbcmd,devctl,openep,opendevdata,closedev,memset: import usb;
	Rd2h,Rh2d,Rstd,Rdev,Rclass,Riface,Rsetconf,Rgetdesc,Eintr,Ein,Dreport: import usb;
	Dev,Ep: import usb;

Awakemsg	:con int 16rdeaddead;
Diemsg		:con int 16rbeefbeef;
Dwcidle		:con 8;

Setidle		:con 16r0a;
Setproto	:con 16r0b;
Bootproto	:con 0;
KbdCSP		:con int 16r010103;

# scan codes (see kbd.c)
SCesc1		:con byte 16re0;	# first of a 2-character sequence
SCesc2		:con byte 16re1;
SClshift	:con byte 16r2a;
SCrshift	:con byte 16r36;
SCctrl		:con byte 16r1d;
SCcompose	:con byte 16r38;
Keyup		:con byte 16r80;	# flag bit
Keymask		:con byte 16r7f;	# regular scan code bits

# keyboard modifier bits
Mlctrl		:con 0;
Mlshift		:con 1;
Mlalt		:con 2;
Mlgui		:con 3;
Mrctrl		:con 4;
Mrshift		:con 5;
Mralt		:con 6;
Mrgui		:con 7;

# masks for byte[0]
Mctrl		:con byte (1<<Mlctrl | 1<<Mrctrl);
Mshift		:con byte (1<<Mlshift | 1<<Mrshift);
Malt		:con byte (1<<Mlalt | 1<<Mralt);
Mcompose	:con byte (1<<Mlalt);
Maltgr		:con byte (1<<Mralt);
Mgui		:con byte (1<<Mlgui | 1<<Mrgui);

MaxAcc		:con 3;			# max. ptr acceleration
PtrMask		:con 16rf;		# 4 buttons: should allow for more.

workpid, reppid: int;

sctab := array[] of {
	16r0,	16r0,	16r0,	16r0,	16r1e,	16r30,	16r2e,	16r20,
	16r12,	16r21,	16r22,	16r23,	16r17,	16r24,	16r25,	16r26,
	16r32,	16r31,	16r18,	16r19,	16r10,	16r13,	16r1f,	16r14,
	16r16,	16r2f,	16r11,	16r2d,	16r15,	16r2c,	16r2,	16r3,
	16r4,	16r5,	16r6,	16r7,	16r8,	16r9,	16ra,	16rb,
	16r1c,	16r1,	16re,	16rf,	16r39,	16rc,	16rd,	16r1a,
	16r1b,	16r2b,	16r2b,	16r27,	16r28,	16r29,	16r33,	16r34,
	16r35,	16r3a,	16r3b,	16r3c,	16r3d,	16r3e,	16r3f,	16r40,
	16r41,	16r42,	16r43,	16r44,	16r57,	16r58,	16r63,	16r46,
	16r77,	16r52,	16r47,	16r49,	16r53,	16r4f,	16r51,	16r4d,
	16r4b,	16r50,	16r48,	16r45,	16r35,	16r37,	16r4a,	16r4e,
	16r1c,	16r4f,	16r50,	16r51,	16r4b,	16r4c,	16r4d,	16r47,
	16r48,	16r49,	16r52,	16r53,	16r56,	16r7f,	16r74,	16r75,
	16r55,	16r59,	16r5a,	16r5b,	16r5c,	16r5d,	16r5e,	16r5f,
	16r78,	16r79,	16r7a,	16r7b,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r71,
	16r73,	16r72,	16r0,	16r0,	16r0,	16r7c,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r1d,	16r2a,	16r38,	16r7d,	16r61,	16r36,	16r64,	16r7e,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r73,	16r72,	16r71,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,	16r0,
};

Kin : adt {
	name: string;
	fd: ref Sys->FD;
};
kbdin : ref Kin;

KDev : adt {
	dev: ref Dev;	# usb device
	ep: ref Dev;	# endpoint to get events
	in: ref Kin;		# used to send events to kernel
	idle: int;		# min time between reports (× 4ms)
	repeatc: chan of int;	# only for keyboard
	pidc: chan of int;
	accel: int;		# only for mouse
	bootp: int;		# has associated keyboard
	debug: int;
};

setbootproto(f: ref KDev, eid: int): int {
	nr, r, id: int;

	r = Rh2d|Rclass|Riface;
	dprint("setting boot protocol\n");
	id = f.dev.usb.ep[eid].iface.id;
	nr = usbcmd(f.dev, r, Setproto, Bootproto, id, nil, 0);
	if(nr < 0)
		return -1;
	usbcmd(f.dev, r, Setidle, f.idle<<8, id, nil, 0);
	return nr;
}

hasesc1(sc: byte): int { return (((sc) > byte 16r47) || ((sc) == byte 16r38)); }

stoprepeat(f: ref KDev) {
	f.repeatc <- = Awakemsg;
}

startrepeat(f: ref KDev, esc1,sc: byte) {
	c: int;
	if(int esc1)
		c = int SCesc1 << 8 | int (sc & byte 16rff);
	else	c = int sc;
	f.repeatc <- = c;
}

repeatproc(f: ref KDev) {
	pid := sys->pctl(0, nil);
	f.pidc <-= pid;
	l := Awakemsg;
	Repeat: do {
		if(l == Diemsg) return;
		while(l == Awakemsg)
			l = <- f.repeatc;
		if(l == Diemsg) return;
		esc1 := l >> 8;
		sc := l;
		t := 160;
		for(;;){
			l = <- f.repeatc;
			#for(i := 0; i < t; i += 5){
			#	alt {
			#	l = <- f.repeatc => { continue Repeat; }
			#	* => {}
			#	}
			#	sys->sleep(5);
			#}
			#putscan(f, byte esc1, byte sc);
			#t = 30;
		}
	} while(0);
}

putscan(f: ref KDev, esc, sc: byte) {
	s := array[2] of {byte SCesc1, byte 0};

	kbinfd := f.in.fd;
	if(sc == byte 16r41){
		f.debug += 2;
		return;
	}
	if(sc == byte 16r42){
		f.debug = 0;
		return;
	}
	sys->fprint(sys->fildes(2), "");
	if(f.debug > 1)
		if(int esc)	sys->fprint(sys->fildes(2), "sc: %x %x\n", int SCesc1, int sc);
		else		sys->fprint(sys->fildes(2), "sc: %x %x\n", 0, int sc);
	s[1] = sc;
	if(int esc && int sc != 0)
		sys->write(kbinfd, s, 2);
	else if(int sc != 0)
		sys->write(kbinfd, s[1:], 1);
}

putmod(f: ref KDev, mods, omods, mask, esc, sc: byte) {
	if(int (mods&mask) && ! int (omods&mask))
		putscan(f, esc, sc);
	if(! int (mods&mask) && int (omods&mask))
		putscan(f, esc, Keyup|sc);
}

putkeys(f: ref KDev, buf,obuf: array of byte, n: int, dk: byte): byte {
	i,j: int;
	uk: byte;

	putmod(f, buf[0], obuf[0], Mctrl, byte 0, SCctrl);
	putmod(f, buf[0], obuf[0], byte (1<<Mlshift), byte 0, SClshift);
	putmod(f, buf[0], obuf[0], byte (1<<Mrshift), byte 0, SCrshift);
	putmod(f, buf[0], obuf[0], Mcompose, byte 0, SCcompose);
	putmod(f, buf[0], obuf[0], Maltgr, byte 1, SCcompose);

	# Report key downs
	for(i = 2; i < n; i++){
		br1: for(j = 2; j < n; j++)
			if(buf[i] == obuf[j])
				break br1;
		if(j == n && int buf[i] != 0){
			dk = byte sctab[int buf[i]];
			putscan(f, byte hasesc1(dk), dk);
			startrepeat(f, byte hasesc1(dk), dk);
		}
	}

	# Report key ups
	uk = byte 0;
	for(i = 2; i < n; i++){
		br2: for(j = 2; j < n; j++)
			if(obuf[i] == buf[j])
				break br2;
		if(j == n && obuf[i] != byte 0){
			uk = byte sctab[int obuf[i]];
			putscan(f, byte hasesc1(uk), uk|Keyup);
		}
	}
	if(int uk && (dk == byte 0 || dk == uk)){
		stoprepeat(f);
		dk = byte 0;
	}
	return dk;
}

setfirstconfig(f: ref KDev, eid: int, desc: array of byte, descsz: int): int {
	nr, r, id, i: int;
	ignoredesc := array[128] of byte;

	dprint("setting first config\n");
	if(desc == nil){
		descsz = len ignoredesc;
		desc = ignoredesc;
	}

	id = f.dev.usb.ep[eid].iface.id;
	r = Rh2d | Rstd | Rdev;
	nr = usbcmd(f.dev, r, Rsetconf, 1, 0, nil, 0);
	if(nr < 0) return -1;

	r = Rh2d | Rclass | Riface;
	nr = usbcmd(f.dev, r, Setidle, f.idle<<8, id, nil, 0);
	if(nr < 0) return -1;

	r = Rd2h | Rstd | Riface;
	nr = usbcmd(f.dev,  r, Rgetdesc, Dreport<<8, id, desc, descsz);
	if(nr <= 0) return -1;

	if(f.debug){
		fprint(fildes(2), "report descriptor:");
		for(i = 0; i < nr; i++){
			if(i%8 == 0)
				fprint(fildes(2), "\n\t");
			fprint(fildes(2), "%#2.2ux ", int desc[i]);
		}
		fprint(fildes(2), "\n");
	}
	#f.ptrvals = ptrrepvals;
	return nr;
}

# Try to recover from a babble error. A port reset is the only way out.
# BUG: we should be careful not to reset a bundle with several devices.
recoverkb(f: ref KDev) {
	f.dev.dfd = nil;	# it's for usbd now
	devctl(f.dev, "reset");
	for(i := 0; i < 10; i++){
		if(i == 5)
			f.bootp++;
		sys->sleep(500);
		if(opendevdata(f.dev, Sys->ORDWR) != nil){
			if(f.bootp)
				# TODO func pointer
				setbootproto(f, f.ep.id);
			else
				setfirstconfig(f, f.ep.id, nil, 0);
			break;
		}
		# else usbd still working...
	}
}

kbfatal(kd: ref KDev, sts: string) {
	if(sts != nil)
		sys->fprint(sys->fildes(2), "kb: fatal: %s\n", sts);
	else	sys->fprint(sys->fildes(2), "kb: exiting\n");
	# non blocking???
	if(kd.repeatc != nil)
		kd.repeatc <- = Diemsg;
	dev := kd.dev;
	kd.dev = nil;
	if(kd.ep != nil)
		closedev(kd.ep);
	kd.ep = nil;
	devctl(dev, "detach");
	closedev(dev);
}

kbdbusy(buf: array of byte, n: int): int {
	for(i := 1; i < n; i++)
		if(buf[i] == byte 0 || buf[i] != buf[0])
			return 0;
	return 1;
}

kbdwork(f: ref KDev) {
	dk: int;
	nerrs: int;
	buf := array[f.ep.maxpkt] of byte;
	lbuf := array[f.ep.maxpkt] of byte;
	err: string;

	pid := sys->pctl(0, nil);
	f.pidc <-= pid;

	kbdfd := f.ep.dfd;

	if(f.ep.maxpkt < 3 || f.ep.maxpkt > 64)
		kbfatal(f, "weird maxpkt");

	f.repeatc = chan of int;
	spawn repeatproc(f);

	memset(lbuf,0);
	dk = nerrs = 0;

	while(1) {
		memset(buf,0);
		c := sys->read(kbdfd, buf, f.ep.maxpkt);
		if(c < 0){
			sys->fprint(sys->fildes(2), "kb: %s: read: %r\n", f.ep.dir);
			err = sys->sprint("%r");
			sys->fprint(sys->fildes(2), "kb: %s: read: %s\n", f.ep.dir, err);
			if(err =="babble" && ++nerrs < 3){
				#TODO!
				recoverkb(f);
				continue;
			}
		}
		if(c <=0)
			kbfatal(f, nil);
		if(c <3)
			continue;
		if(kbdbusy(buf[2:], c-2))
			continue;
		if(usbdebug > 2 || f.debug > 1){
			sys->fprint(sys->fildes(2), "kbd mod %x: ", int buf[0]);
			for(i := 2; i < c; i++)
				sys->fprint(sys->fildes(2), "kc %x ", int buf[i]);
			sys->fprint(sys->fildes(2), "\n");
		}
		dk = int putkeys(f, buf, lbuf, f.ep.maxpkt, byte dk);
		for(j:=0;j< len buf;j++) lbuf[j]=buf[j];
		nerrs = 0;
	}
}

kbstart(d: ref Dev, ep: ref Ep, in: ref Kin, nil: ref fn(f: ref KDev), kd: ref KDev) {
	desc := array[512] of byte;
	n, res :int;

	if(in.fd ==nil){
		in.fd = sys->open(in.name, sys->OWRITE);
		if(in.fd ==nil){
			sys->fprint(sys->fildes(2), "kb: %s: %r\n", in.name);
			return;
		}
	}

	kd.in = in;
	kd.dev = d;
	res = -1;
	kd.ep = openep(d, ep.id);
	if(kd.ep ==nil){
		sys->fprint(sys->fildes(2), "kb: %s: openep %d: %r\n", d.dir, ep.id);
		return;
	}

	#
	# DWC OTG controller misses some split transaction inputs.
	# Set nonzero idle time to return more frequent reports
	# of keyboard state, to avoid losing key up/down events.
	#
	n = sys->read(d.cfd, desc, len desc);
	if(n > 0){
		(nil,s1) := str->splitstrr(string desc[:n],"dwcotg");
		if (s1 != string desc[:n])
			kd.idle = Dwcidle;
	}
	kd.bootp = 1;
	if(setbootproto(kd, ep.id) < 0){
		sys->fprint(sys->fildes(2), "kb: %s: bootproto: %r\n", d.dir);
		return;
	}

	if(opendevdata(kd.ep, sys->OREAD) ==nil){
		sys->fprint(sys->fildes(2), "kb: %s: opendevdata: %r\n", kd.ep.dir);
		closedev(kd.ep);
		kd.ep = nil;
		return;
	}

	spawn kbdwork(kd);
	workpid =<- kd.pidc;
	reppid =<- kd.pidc;
}

init(u: Usb, d: ref Dev): int {
	usb = u;
	workpid = reppid = -1;

	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	kbdin = ref Kin;
	kbdin.name = "#Ι/kbin";

	debug := 0;

	ud := d.usb;
	ep: ref Ep;

	for(i := 0; i < len ud.ep; i++){
		if((ep = ud.ep[i]) == nil)
			continue;
		if(ep.typ == Eintr
		   && ep.dir == Ein
		   && ep.iface.csp == KbdCSP){
			kd := ref KDev;
			kd.accel = 0;
			kd.bootp = 1;
			kd.debug = debug;
			kd.pidc = chan of int;
			kbstart(d, ep, kbdin, kbdwork, kd);
		}
	}
	return 0;
}

kill(pid: int): int {
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

shutdown() {
	if(workpid >= 0) kill(workpid);
	if(reppid >= 0) kill(reppid);
	kbdin.fd = nil;
}
