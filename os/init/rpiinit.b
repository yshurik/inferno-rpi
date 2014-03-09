
implement Init;

include "sys.m";
	sys: Sys;
include "sh.m";
	sh: Sh;
include "draw.m";

Shell: module { init: fn(ctxt: ref Draw->Context, argv: list of string); };
Disk: module { init: fn(ctxt: ref Draw->Context, argv: list of string); };
Init: module { init: fn(ctxt: ref Draw->Context, argv: list of string); };
Usbd: module { init: fn(ctxt: ref Draw->Context, argv: list of string); };

err(s: string) { sys->fprint(sys->fildes(2), "init: %s\n", s); }

dobind(f, t: string, flags: int) {
	if(sys->bind(f, t, flags) < 0)
		err(sys->sprint("can't bind %s on %s: %r", f, t));
}

init(nil: ref Draw->Context, nil: list of string)
{
	shell := load Shell "/dis/sh.dis";
	usbd := load Usbd "/dis/usb/usbd.dis";
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;

	dobind("#S",  "/dev", sys->MAFTER);	# sdcard subsystem
	sh->system(nil, "disk/fdisk -p /dev/sdM0/data > /dev/sdM0/ctl");
	sh->system(nil, "mount -c {disk/kfs -c -A -n main /dev/sdM0/plan9} /n/local");
	sys->bind("/n/local/dis", "/dis", Sys->MREPL);
	sys->bind("/n/local/lib", "/lib", Sys->MREPL);
	sys->bind("/n/local/usr", "/usr", Sys->MREPL);
	sys->bind("/n/local/man", "/man", sys->MREPL);
	sys->bind("/n/local/fonts", "/fonts", sys->MREPL);
	sys->bind("/n/local/icons", "/icons", sys->MREPL);
	sys->bind("/n/local/module", "/module", sys->MREPL);
	sys->bind("/n/local/locale", "/locale", sys->MREPL);

	dobind("#p",  "/prog", sys->MREPL);
	dobind("#i",  "/dev", sys->MREPL);	# draw device
	dobind("#c",  "/dev", sys->MAFTER);	# console device
	dobind("#u",  "/dev", sys->MAFTER);	# usb subsystem
	dobind("#e",  "/env", sys->MREPL|sys->MCREATE);
	dobind("#l0", "/net", Sys->MREPL);
	dobind("#I",  "/net", sys->MAFTER);	# IP

	usbd->init(nil,nil);
	#sh->system(nil, "ndb/cs");
	spawn shell->init(nil, nil);
}

