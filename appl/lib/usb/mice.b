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

Setproto	:con 16r0b;
Bootproto	:con 0;
PtrCSP		:con 16r020103;
MaxChLen	:con 64;
Setidle		:con 16r0a;

KindPad		:con 0;
KindButtons	:con 1;
KindX		:con 2;
KindY		:con 3;
KindWheel	:con 4;

MaxVals		:con 16;
MaxIfc		:con 8;

HidReportApp	:con 16r01;
HidTypeUsgPg	:con 16r05;
HidPgButts	:con 16r09;

HidTypeRepSz	:con 16r75;
HidTypeCnt	:con 16r95;
HidCollection	:con 16ra1;

HidTypeUsg	:con 16r09;
HidPtr		:con 16r01;
HidX		:con 16r30;
HidY		:con 16r31;
HidZ		:con 16r32;
HidWheel	:con 16r38;

HidInput	:con 16r81;
HidReportId	:con 16r85;
HidReportIdPtr	:con 16r01;

HidEnd		:con 16rc0;

MaxAcc		:con 3;			# max. ptr acceleration
PtrMask		:con 16rf;		# 4 buttons: should allow for more.

workpid: int;


HidInterface : adt {
	v: array of int;	# MaxVals, one ulong per val should be enough
	kind: array of byte;	# MaxVals
	nbits: int;
	count: int;
};
mkhidinterface(): ref HidInterface {
	hi := ref HidInterface;
	hi.v = array[MaxVals] of int;
	hi.kind = array[MaxVals] of byte;
	return hi;
}

HidRepTempl : adt {
	id: int;			# id which may not be present
	sz: int;			# in bytes
	nifcs: int;
	ifcs: array of ref HidInterface;	# MaxIfc
};
mkhidreptempl(): ref HidRepTempl {
	hrt := ref HidRepTempl;
	hrt.ifcs = array[MaxIfc] of ref HidInterface;
	for(i:=0;i<MaxIfc;i++)
		hrt.ifcs[i] = mkhidinterface();
	return hrt;
}

Kin : adt {
	name: string;
	fd: ref Sys->FD;
};

KDev : adt {
	dev: ref Dev;		# usb device
	ep: ref Dev;		# endpoint to get events
	in: ref Kin;		# used to send events to kernel
	idle: int;		# min time between reports (× 4ms)
	pidc: chan of int;
	accel: int;		# only for mouse
	bootp: int;		# has associated keyboard
	debug: int;
	templ: ref HidRepTempl;
};
mkkdev(): ref KDev {
	kd := ref KDev;
	kd.templ = mkhidreptempl();
	return kd;
}

Chain: adt {
	b: int;			# offset start in bits, (first full)
	e: int;			# offset end in bits (first empty)
	buf: array of byte;	#MaxChLen;
};
mkchain(): ref Chain {
	c := ref Chain;
	c.buf = array[MaxChLen] of byte;
	return c;
}

dumpreport(templ: ref HidRepTempl) {
	i, j, ifssz: int;
	ifs: array of ref HidInterface;

	ifssz = templ.nifcs;
	ifs = templ.ifcs;
	for(i = 0; i < ifssz; i++){
		fprint(fildes(2), "\tcount %#ux", ifs[i].count);
		fprint(fildes(2), " nbits %d ", ifs[i].nbits);
		fprint(fildes(2), "\n");
		for(j = 0; j < ifs[i].count; j++){
			fprint(fildes(2), "\t\tkind %#ux ", int ifs[i].kind[j]);
			fprint(fildes(2), "v %#ux\n", int ifs[i].v[j]);
		}
		fprint(fildes(2), "\n");
	}
	fprint(fildes(2), "\n");
}


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
		fprint(fildes(2), "kb: fatal: %s\n", sts);
	else	fprint(fildes(2), "kb: exiting\n");

	dev := kd.dev;
	kd.dev = nil;
	if(kd.ep != nil)
		closedev(kd.ep);
	kd.ep = nil;
	devctl(dev, "detach");
	closedev(dev);
}

#define MSK(nbits)		((1UL << (nbits)) - 1)
MSK(nbits: int):byte { return byte ((big 1 << (nbits)) - big 1); }
#define IsCut(bbits, ebits)	(((ebits)/8 - (bbits)/8) > 0)
IsCut(bbits, ebits: int):int { return (((ebits)/8 - (bbits)/8) > 0); }

# Get, at most, 8 bits
get8bits(ch: ref Chain, nbits: int): byte {
	b, nbyb, nbib, nlb :int;
	low, high :byte;

	b = ch.b + nbits - 1;
	nbib = ch.b % 8;
	nbyb = ch.b / 8;
	nlb = 8 - nbib;
	if(nlb > nbits)
		nlb = nbits;

	low = MSK(nlb) & (ch.buf[nbyb] >> nbib);
	if(IsCut(ch.b, b))
		high = (ch.buf[nbyb + 1] & MSK(nbib)) << nlb;
	else
		high = byte 0;
	ch.b += nbits;
	return MSK(nbits)&(high | low);
}

getbits(vp: array of byte, ch: ref Chain, nbits: int) {
	nby := nbits / 8;
	nbi := nbits % 8;

	for(i := 0; i < nby; i++)
		vp[i] = get8bits(ch, 8);

	if(nbi != 0)
		vp[nby] = get8bits(ch, nbi);
}

parsereportdesc(temp: ref HidRepTempl, repdesc: array of byte, repsz: int): int {
	i, j, l, n, isptr, hasxy, hasbut, nk, ncoll, dsize: int;
	ks := array[MaxVals+1] of byte;

	isptr = 0;
	hasxy = hasbut = 0;
	ncoll = 0;
	n = 0;
	nk = 0;
	#memset(ifs, 0, (len temp.ifcs) * MaxIfc);
	for(i = 0; i < repsz; i += dsize+1){
		dsize = (1 << (int repdesc[i] & 03)) >> 1;
		if(nk > MaxVals){
			fprint(fildes(2), "bad report: too many input types\n");
			return -1;
		}
		if(n == MaxIfc)
			break;
		if(repdesc[i] == byte HidEnd){
			ncoll--;
			if(ncoll == 0)
				break;
		}

		case (int repdesc[i]){
		HidReportId =>
			case (int repdesc[i+1]){
			HidReportIdPtr =>
				temp.id = int repdesc[i+1];
				break;
			* =>
				fprint(fildes(2), "report type %#ux bad\n",
					int repdesc[i+1]);
				return -1;
			}
			break;
		HidTypeUsg =>
			case (int repdesc[i+1]){
			HidX =>
				hasxy++;
				ks[nk++] = byte KindX;
				break;
			HidY =>
				hasxy++;
				ks[nk++] = byte KindY;
				break;
			HidZ =>
				ks[nk++] = byte KindPad;
				break;
			HidWheel =>
				ks[nk++] = byte KindWheel;
				break;
			HidPtr =>
				isptr++;
				break;
			}
			break;
		HidTypeUsgPg =>
			case (int repdesc[i+1]){
			HidPgButts =>
				hasbut++;
				ks[nk++] = byte KindButtons;
				break;
			}
			break;
		HidTypeRepSz =>
			temp.ifcs[n].nbits = int repdesc[i+1];
			break;
		HidTypeCnt =>
			temp.ifcs[n].count = int repdesc[i+1];
			break;
		HidInput =>
			if(temp.ifcs[n].count > MaxVals){
				fprint(fildes(2), "bad report: input count too big\n");
				return -1;
			}
			for(j = 0; j <nk; j++)
				temp.ifcs[n].kind[j] = ks[j];
			if(nk != 0 && nk < temp.ifcs[n].count)
				for(l = j; l <temp.ifcs[n].count; l++)
					temp.ifcs[n].kind[l] = ks[j-1];
			n++;
			if(n < MaxIfc){
				temp.ifcs[n].count = temp.ifcs[n-1].count;	# inherit values
				temp.ifcs[n].nbits = temp.ifcs[n-1].nbits;
				if(temp.ifcs[n].nbits == 0)
					temp.ifcs[n].nbits = 1;
			}
			nk = 0;
			break;
		HidCollection =>
			ncoll++;
			break;
		}
	}
	temp.nifcs = n;
	for(i = 0; i < n; i++)
		temp.sz += temp.ifcs[i].nbits * temp.ifcs[i].count;
	temp.sz = (temp.sz + 7) / 8;

	if(isptr && hasxy && hasbut)
		return 0;
	fprint(fildes(2), "bad report: isptr %d, hasxy %d, hasbut %d\n",
		isptr, hasxy, hasbut);
	return -1;
}

parsereport(templ: ref HidRepTempl, rep: ref Chain): int {
	p := array[4] of byte;
	ifssz := templ.nifcs;
	ifs := templ.ifcs;
	for(i := 0; i < ifssz; i++)
		for(j := 0; j < ifs[i].count; j++){
			#if(ifs[i].nbits > 8 * sizeof ifs[i].v[0]){
			if(ifs[i].nbits > 8 * 8){
				fprint(fildes(2), "ptr: bad bits in parsereport\n");
				return -1;
			}
			p[0]=p[1]=p[2]=p[3]= byte 0;
			getbits(p, rep, ifs[i].nbits);
			# le to host
			ifs[i].v[j] = int p[3]<<24 | int p[2]<<16 | int p[1]<<8 | int p[0]<<0;
			k := int ifs[i].kind[j];
			if(k == KindX || k == KindY || k == KindWheel){
				# propagate sign
				if(int ifs[i].v[j] & (1 << (ifs[i].nbits - 1)))
					ifs[i].v[j] |= int ~MSK(ifs[i].nbits);
			}
		}
	return 0;
}

# could precalculate indices after parsing the descriptor
hidifcval(templ: ref HidRepTempl, kind, n: int): int {
	ifssz := templ.nifcs;
	for(i := 0; i < ifssz; i++)
		for(j := 0; j < templ.ifcs[i].count; j++)
			if(int templ.ifcs[i].kind[j] == kind && n-- == 0)
				return int templ.ifcs[i].v[j];
	return 0;		# least damage (no buttons, no movement)
}

ptrrepvals(kd: ref KDev, ch: ref Chain): (int,int,int,int) {
	x, y, b: int;
	buts := array[] of {byte 0, byte 2, byte 1};

	c := ch.e / 8;

	# sometimes there is a report id, sometimes not
	if(c == kd.templ.sz + 1)
		if(int ch.buf[0] == kd.templ.id)
			ch.b += 8;
		else
			return (-1,-1,-1,-1);

	parsereport(kd.templ, ch);

	if(kd.debug > 1)
		dumpreport(kd.templ);
	if(c < 3)
		return (-1,-1,-1,-1);

	x = hidifcval(kd.templ, KindX, 0);
	y = hidifcval(kd.templ, KindY, 0);
	b = 0;
	for(i := 0; i< len buts; i++)
		b |= (hidifcval(kd.templ, KindButtons, i) & 1) << int buts[i];
	if(c > 3 && hidifcval(kd.templ, KindWheel, 0) > 0)	# up
		b |= 16r08;
	if(c > 3 && hidifcval(kd.templ, KindWheel, 0) < 0)	# down
		b |= 16r10;

	return (0,x,y,b);
}

scale(f: ref KDev, x: int): int {
	sign := 1;
	if(x < 0){
		sign = -1;
		x = -x;
	}
	case(x){
	0 => ;
	1 => ;
	2 => ;
	3 =>
		break;
	4 =>
		x = 6 + (f.accel>>2);
		break;
	5 =>
		x = 9 + (f.accel>>1);
		break;
	* =>
		x *= MaxAcc;
		break;
	}
	return sign*x;
}

ptrwork(f: ref KDev) {
	hipri, nerrs, r, x, y, b, c :int;
	mfd, ptrfd: ref Sys->FD;
	ch := mkchain();

	pid := pctl(0, nil);
	f.pidc <-= pid;

	curx := 0;
	cury := 0;

	hipri = nerrs = 0;
	ptrfd = f.ep.dfd;
	mfd = f.in.fd;
	if(f.ep.maxpkt < 3 || f.ep.maxpkt > MaxChLen)
		kbfatal(f, "weird mouse maxpkt");
	for(;;){
		memset(ch.buf, 0);
		if(f.ep == nil)
			kbfatal(f, nil);
		c = read(ptrfd, ch.buf, f.ep.maxpkt);
		if(c < 0){
			dprint(sprint("kb: mouse: %s: read: %r\n", f.ep.dir));
			if(++nerrs < 3){
				recoverkb(f);
				continue;
			}
		}
		if(c <= 0)
			kbfatal(f, nil);
		ch.b = 0;
		ch.e = 8 * c;
		(r,x,y,b) = ptrrepvals(f,ch);
		if(f.debug > 1)
			fprint(fildes(2), "ptrrepvals: m%11d %11d %11d\n", x, y, b);
		if(r < 0)
			continue;
		if(f.accel){
			x = scale(f, x);
			y = scale(f, y);
		}
		if(x >= 128) x = x - 256;
		if(y >= 128) y = y - 256;

		curx += x;
		cury += y;
		if (curx<0) curx =0;
		if (cury<0) cury =0;
		if (curx>1280) curx =1280;
		if (cury>1024) cury =1024;

		if(f.debug > 1)
			fprint(fildes(2), "kb: m%11d %11d %11d\n", curx, cury, b);
		mbuf := sys->aprint("m%11d %11d %11d", curx, cury,b);
		if(write(mfd, mbuf, len mbuf) < 0)
			kbfatal(f, "mousein i/o");
		if(hipri == 0){
			#sethipri();
			hipri = 1;
		}
	}
}

setfirstconfig(f: ref KDev, eid: int, desc: array of byte, descsz: int): int {
	nr, r, id, i: int;
	ignoredesc := array[64] of byte;

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

kbstart(d: ref Dev, ep: ref Ep, in: ref Kin, nil: ref fn(f: ref KDev), kd: ref KDev) {
	desc := array[128] of byte;
	n, res :int;

	if(in.fd ==nil){
		in.fd = open(in.name, sys->OWRITE);
		if(in.fd ==nil){
			fprint(fildes(2), "kb: %s: %r\n", in.name);
			return;
		}
	}

	kd.in = in;
	kd.dev = d;
	res = -1;
	kd.ep = openep(d, ep.id);
	if(kd.ep ==nil){
		fprint(fildes(2), "kb: %s: openep %d: %r\n", d.dir, ep.id);
		return;
	}

	res= setfirstconfig(kd, ep.id, desc, len desc);
	if(res > 0)
		res = parsereportdesc(kd.templ, desc, len desc);

	# if we could not set the first config, we give up
	if(res < 0){
		kd.bootp = 1;
		if(setbootproto(kd, ep.id) < 0){
			fprint(fildes(2), "kb: %s: bootproto: %r\n", d.dir);
			return;
		}
	}
	else if(kd.debug)
		dumpreport(kd.templ);

	if(opendevdata(kd.ep, sys->OREAD) ==nil){
		fprint(fildes(2), "kb: %s: opendevdata: %r\n", kd.ep.dir);
		closedev(kd.ep);
		kd.ep = nil;
		return;
	}

	spawn ptrwork(kd);
	workpid =<- kd.pidc;
}

init(u: Usb, d: ref Dev): int {
	workpid = -1;

	usb = u;
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	ptrin := ref Kin;
	ptrin.name = "#m/pointerin";

	bootp := 0;
	debug := 0;
	accel := 0;

	ud := d.usb;
	ep: ref Ep;

	for(i := 0; i < len ud.ep; i++){
		if((ep = ud.ep[i]) == nil)
			continue;
		if(ep.typ == Eintr
		   && ep.dir == Ein
		   && ep.iface.csp == PtrCSP){
			kd := mkkdev();
			kd.accel = accel;
			kd.bootp = bootp;
			kd.debug = debug;
			kd.pidc = chan of int;
			kbstart(d, ep, ptrin, ptrwork, kd);
		}
	}
	return 0;
}

kill(pid: int): int {
	fd := open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

shutdown()
{
	if(workpid >= 0)
		kill(workpid);
}
