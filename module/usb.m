
Usb: module
{
	PATH: con "/dis/lib/usb/usb.dis";
	DATABASEPATH: con "/lib/usbdb";

	Nep	:con 16;	# max. endpoints per usb device & per interface
	Nconf	:con 16;	# max. configurations per usb device
	Naltc	:con 16;	# max. alt configurations per interface
	Niface	:con 16;
	Nddesc	:con 8*Nep;	# max. device-specific descriptors per usb device
	Uctries :con 4;
	Ucdelay :con 50;	# delay before retrying

	pollms: con 1000;

	# request type
	Rh2d	:con 0<<7;	# host to device
	Rd2h	:con 1<<7;	# device to host

	Rstd	:con 0<<5;	# types
	Rclass	:con 1<<5;
	Rvendor	:con 2<<5;

	Rdev	:con 0;		# recipients
	Riface	:con 1;
	Rep	:con 2;		# endpoint
	Rother	:con 3;

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
	Dhublen 	:con 9;		# hub descriptor length

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
	mkhub: fn(): ref Hub;

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
	mkport: fn(): ref Port;

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
		usb: ref Usbdev;	# USB description */
		mod: UsbDriver;
	};

	#
	# device description as reported by USB (unpacked).
	#
	Usbdev: adt {
		csp: int;			# USB class/subclass/proto
		vid: int;			# vendor id
		did: int;			# product (device) id
		dno: int;			# device release number
		vendor: string;
		product: string;
		serial: string;
		vsid: int;
		psid: int;
		ssid: int;
		class: int;			# from descriptor
		subclass: int;
		proto: int;
		nconf: int;			# from descriptor
		ep: array of ref Ep;		# Nep all endpoints in device
		conf: array of ref Conf;	# Nconf configurations
		ddesc: array of ref Desc;	# Nddesc (raw) device specific descriptors
	};
	mkusbdev: fn(): ref Usbdev;

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
	mkep: fn(d: ref Usbdev, id: int): ref Ep;

	Altc: adt {
		attrib: int;
		interval: int;
	};

	Iface: adt {
		id: int;		# interface number */
		csp: int;		# USB class/subclass/proto */
		altc: array of ref Altc;
		ep: cyclic array of ref Ep;
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

	devnameid: fn(s: string): int; # epN.M -> N
	opendev: fn(fnm: string): ref Dev;
	opendevdata: fn(d: ref Dev, mode: int): ref Sys->FD;
	openep: fn(d: ref Dev, id: int): ref Dev;
	devctl: fn(d: ref Dev, s: string):int;

	hex: fn(buf: array of byte): string;

	cmdreq: fn(d: ref Dev, typ, req, val, idx: int, outbuf: array of byte, count: int): int;
	cmdrep: fn(d: ref Dev, buf: array of byte, nb: int): int;
	usbcmd: fn(d: ref Dev, typ, req, val, idx: int, data: array of byte, count: int): int;

	getmaxpkt: fn(d: ref Dev, islow: int): int;
	unstall: fn(dev: ref Dev, ep: ref Dev, dir: int): int;

	parsedev: fn(xd: ref Dev, b: array of byte, n: int): int;
	parseiface: fn(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): (int, ref Iface, ref Altc);
	parseendpt: fn(d: ref Usbdev, c: ref Conf, ip: ref Iface, altc: ref Altc, b: array of byte, n: int): (int, ref Ep);
	parsedesc: fn(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): int;
	parseconf: fn(d: ref Usbdev, c: ref Conf, b: array of byte, n: int): int;

	configdev: fn(d: ref Dev): int;
	classname: fn(i: int): string;
	writeinfo: fn(d: ref Dev);

	closeconf: fn(c: ref Conf);
	closedev: fn(d: ref Dev);

	argv0: string;
	usbdebug: int;
	dprint: fn(s: string);

	Class: fn(csp:int): int;
	Subclass: fn(csp:int): int;
	Proto: fn(csp:int): int;
	CSP: fn(c,s,p:int): int;

	init: fn();
	get2: fn(b: array of byte): int;
	put2: fn(buf: array of byte, v: int);
	get4: fn(b: array of byte): int;
	put4: fn(buf: array of byte, v: int);
	bigget2: fn(b: array of byte): int;
	bigput2: fn(buf: array of byte, v: int);
	bigget4: fn(b: array of byte): int;
	bigput4: fn(buf: array of byte, v: int);
	memset: fn(b: array of byte, v: int);
	strtol: fn(s: string, base: int): (int, string);
};

UsbDriver: module
{
	init: fn(usb: Usb, dev: ref Usb->Dev): int;
	shutdown: fn();
};


