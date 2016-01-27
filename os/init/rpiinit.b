
implement Init;

include "sys.m";
	sys: Sys;
	print: import sys;
include "sh.m";
	sh: Sh;
include "draw.m";
	draw: Draw;
	Context: import draw;

Shell: module { init: fn(ctxt: ref Context, argv: list of string); };
Disk: module { init: fn(ctxt: ref Context, argv: list of string); };
Init: module { init: fn(ctxt: ref Context, argv: list of string); };
Usbd: module { init: fn(ctxt: ref Context, argv: list of string); };
Cmd: module { init: fn(ctxt: ref Context, argv: list of string); };

err(s: string) { sys->fprint(sys->fildes(2), "init: %s\n", s); }

dobind(f, t: string, flags: int) {
	if(sys->bind(f, t, flags) < 0)
		err(sys->sprint("can't bind %s on %s: %r", f, t));
}

bindsd() {
	sys->bind("/n/local/sd/dis", "/dis", Sys->MREPL);
	sys->bind("/n/local/sd/lib", "/lib", Sys->MREPL);
	sys->bind("/n/local/sd/usr", "/usr", Sys->MREPL);
	sys->bind("/n/local/sd/man", "/man", sys->MREPL);
	sys->bind("/n/local/sd/fonts", "/fonts", sys->MREPL);
	sys->bind("/n/local/sd/icons", "/icons", sys->MREPL);
	sys->bind("/n/local/sd/module", "/module", sys->MREPL);
	sys->bind("/n/local/sd/locale", "/locale", sys->MREPL);
	sys->bind("/n/local/sd/services", "/services", sys->MREPL);
	sys->bind("/n/local/sd/tmp", "/tmp", sys->MREPL|sys->MCREATE);
}

init(nil: ref Context, nil: list of string)
{
	shell := load Shell "/dis/sh.dis";
	usbd := load Usbd "/dis/usb/usbd.dis";
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;

	# just use dos-based sd card
	dobind("#S",  "/dev", sys->MAFTER);	# sdcard subsystem
	sh->system(nil, "mount -c {mntgen} /n");
	sh->system(nil, "mount -c {mntgen} /n/local");
	sh->system(nil, "mount -c {mntgen} /n/remote");
	sh->system(nil, "disk/fdisk -p /dev/sdM0/data > /dev/sdM0/ctl");
	sh->system(nil, "dossrv -f /dev/sdM0/dos -m /n/local/sd");

	#sh->system(nil, "mount -c {disk/kfs -c -A -n main /dev/sdM0/plan9} /n/local/sd");
	#sh->system(nil, "disk/kfscmd allow");

	bindsd();

	dobind("#p",  "/prog", sys->MREPL);
	dobind("#i",  "/dev", sys->MREPL);	# draw device
	dobind("#m",  "/dev", sys->MAFTER);	# mouse device
	dobind("#c",  "/dev", sys->MAFTER);	# console device
	dobind("#u",  "/dev", sys->MAFTER);	# usb subsystem
	#dobind("#J",  "/dev", sys->MAFTER);	# i2c subsystem
	dobind("#π",  "/dev", sys->MAFTER);	# spi subsystem
	dobind("#G",  "/dev", sys->MAFTER);	# gpio subsystem
	dobind("#e",  "/env", sys->MREPL|sys->MCREATE);
	dobind("#S",  "/dev", sys->MAFTER);	# sdcard subsystem
	dobind("#l0", "/net", Sys->MREPL);
	dobind("#I",  "/net", sys->MAFTER);	# IP

	spawn usbd->init(nil,nil);
	sh->system(nil, "ndb/cs");
	sh->system(nil, "ndb/dns -r");

	sh->system(nil, "styxlisten -A tcp!*!564 export /");

	#sh->system(nil, "wm/wm");

	#uncomment if need a shell instead wm
	spawn shell->init(nil, nil);
}

