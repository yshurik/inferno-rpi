implement UsbDriver;

include "sys.m";
	sys: Sys;
include "usb.m";

Setproto: con 16r0b;
Bootproto: con 0;
PtrCSP: con 16r020103;

workpid: int;

kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

mousework(pidc: chan of int, usb: Usb, d: ref Usb->Dev, fd: ref Sys->FD)
{
	n: int;

	buf := array [d.maxpkt] of byte;
	curx := 0;
	cury := 0;

	pid := sys->pctl(0, nil);
	pidc <-= pid;

	while(1){
		n = sys->read(d.dfd, buf, d.maxpkt);
		if(n < 3){
			sys->sleep(100);
			continue;
		}
		if(usb->usbdebug)
			usb->dprint(sys->sprint("%d: %d\n", sys->millisec(), n));
		dx := int buf[1];
		if(dx >= 128)
			dx = dx - 256;
		dy := int buf[2];
		if(dy >= 128)
			dy = dy - 256;
		curx += dx;
		cury += dy;
		if(curx < 0)
			curx = 0;
		if(cury < 0)
			cury = 0;
		s := sys->aprint("m%d %d %d", curx, cury, int buf[0]);
		sys->write(fd, s, len s);
	}
	if(n < 0 && usb->usbdebug)
		usb->dprint(sys->sprint("read failure in mousework: %r\n"));
	workpid = -1;
}

init(usb: Usb, d: ref Usb->Dev): int
{
	sys = load Sys Sys->PATH;
	sys->print("usbmouse: trace0\n");

	ud := d.usb;
	for(i := 0; i < len ud.ep; ++i)
		if(ud.ep[i] != nil
				 && ud.ep[i].iface.csp == PtrCSP)
			break;

	if(i >= len ud.ep){
		sys->fprint(sys->fildes(2), "failed to find pointer endpoint\n");
		return -1;
	}
	outfd := sys->open("#m/pointer", Sys->OWRITE);
	if(outfd == nil){
		sys->print("usbmouse: failed to open pointer for writing: %r\n");
		return -1;
	}
	sys->print("usbmouse: trace1\n");
	r := Usb->Rh2d|Usb->Rclass|Usb->Riface;
	ret := usb->usbcmd(d, r, Setproto, Bootproto, ud.ep[i].id, nil, 0);
	if(ret >= 0){
		sys->print("usbmouse: trace2\n");
		kep := usb->openep(d, ud.ep[i].id);
		if(kep == nil){
			sys->fprint(sys->fildes(2), "mouse: %s: openep %d: %r\n",
				d.dir, ud.ep[i].id);
			return -1;
		}
		sys->print("usbmouse: trace3\n");
		fd := usb->opendevdata(kep, Sys->OREAD);
		if(fd == nil){
			sys->fprint(sys->fildes(2), "mouse: %s: opendevdata: %r\n", kep.dir);
			usb->closedev(kep);
			return -1;
		}
		sys->print("usbmouse: trace4\n");
		pidc := chan of int;
		spawn mousework(pidc, usb, kep, outfd);
		sys->print("usbmouse: trace5\n");

		workpid =<- pidc;
	}
	else
		sys->fprint(sys->fildes(2), "usbcmd failed: %r\n");
	return ret;
}

shutdown()
{
	if(workpid >= 0)
		kill(workpid);
}
