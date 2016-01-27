
#include "u.h"
#include "../port/lib.h"
#include "dat.h"
#include "mem.h"
#include "fns.h"
#include "version.h"

#include "../port/uart.h"
PhysUart* physuart[1];

Conf conf;
Mach *m = (Mach*)MACHADDR;
Proc *up = 0;

extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;

char* getconf(char*) { return nil; }

void
confinit(void)
{
	ulong base;
	getramsize(&conf);
	conf.topofmem = 128*MB;
	getramsize(&conf);

	base = PGROUND((ulong)end);
	conf.base0 = base;

	conf.npage1 = 0;
	conf.npage0 = (conf.topofmem - base)/BY2PG;
	conf.npage = conf.npage0 + conf.npage1;
	conf.ialloc = (((conf.npage*(main_pool_pcnt))/100)/2)*BY2PG;

	conf.nproc = 100 + ((conf.npage*BY2PG)/MB)*5;
	conf.nmach = 1;

	active.machs = 1;
	active.exiting = 0;

	print("Conf: top=%lud, npage0=%lud, ialloc=%lud, nproc=%lud\n",
			conf.topofmem, conf.npage0,
			conf.ialloc, conf.nproc);
}

static void
poolsizeinit(void)
{
	u64int nb;
	ulong mpb,hpb,ipb;

	nb = conf.npage*BY2PG;
	mpb = (nb*main_pool_pcnt)/100;
	hpb = (nb*heap_pool_pcnt)/100;
	ipb = (nb*image_pool_pcnt)/100;

	poolsize(mainmem, mpb, 0);
	poolsize(heapmem, hpb, 0);
	poolsize(imagmem, ipb, 0);
}

uint
getfirmware(void);

void
main() {
	uint j=0,i=0,k=0;
	uint rev;
	ulong pc;

	pc = getpc();
	pl011_addr((void *)pc, 1);
	pl011_puts("Entered main() at ");
	pl011_addr(&main, 0);
	pl011_puts(" with SP=");
	pl011_addr((void *)getsp(), 0);
	pl011_puts(" with SC=");
	pl011_addr((void *)getsc(), 0);
	pl011_puts(" with CPSR=");
	pl011_addr((void *)getcpsr(), 0);
	pl011_puts(" with SPSR=");
	pl011_addr((void *)getspsr(), 1);

	pl011_puts("Clearing Mach:  ");
	memset(m, 0, sizeof(Mach));
	pl011_addr((char *)m,		0); pl011_puts("-");
	pl011_addr((char *)(m+1),	1);

	pl011_puts("Clearing edata: ");
	memset(edata, 0, end-edata);
	pl011_addr((char *)&edata,	0); pl011_puts("-");
	pl011_addr((char *)&end,	1);

	conf.nmach = 1;

	quotefmtinstall();
	confinit();
	mmuinit1();
	xinit();
	poolinit();
	poolsizeinit();
	//uartconsinit();
	screeninit();
	trapinit();
	timersinit();
	clockinit();
	printinit();
	swcursorinit();

	rev = getfirmware();
	print("\nARM %ld MHz id %8.8lux firmware: rev %d, mem: %ld\n"
		,(m->cpuhz+500000)/1000000, getcpuid(), rev, conf.topofmem/MB);
	print("Inferno OS %s Vita Nuova\n", VERSION);
	print("Ported to Raspberry Pi (BCM2835) by LynxLine\n\n");

	procinit();
	links();
	chandevreset();

	eve = strdup("inferno");

	userinit();
	schedinit();

	pl011_puts("to inifinite loop\n\n");
	for (;;);
}

void
init0(void)
{
	Osenv *o;
	char buf[2*KNAMELEN];

	up->nerrlab = 0;

	//print("Starting init0()\n");
	spllo();

	if(waserror())
		panic("init0 %r");

	/* These are o.k. because rootinit is null.
	 * Then early kproc's will have a root and dot. */

	o = up->env;
	o->pgrp->slash = namec("#/", Atodir, 0, 0);
	cnameclose(o->pgrp->slash->name);
	o->pgrp->slash->name = newcname("/");
	o->pgrp->dot = cclone(o->pgrp->slash);

	chandevinit();

	if(!waserror()){
		ksetenv("cputype", "arm", 0);
		snprint(buf, sizeof(buf), "arm %s", conffile);
		ksetenv("terminal", buf, 0);
		snprint(buf, sizeof(buf), "%s", getethermac());
		ksetenv("ethermac", buf, 0);
		poperror();
	}

	poperror();

	disinit("/osinit.dis");
}

void
userinit(void)
{
	Proc *p;
	Osenv *o;

	p = newproc();
	o = p->env;

	o->fgrp = newfgrp(nil);
	o->pgrp = newpgrp();
	o->egrp = newegrp();
	kstrdup(&o->user, eve);

	strcpy(p->text, "interp");

	p->fpstate = FPINIT;

	/*	Kernel Stack
		N.B. The -12 for the stack pointer is important.
		4 bytes for gotolabel's return PC */
	p->sched.pc = (ulong)init0;
	p->sched.sp = (ulong)p->kstack+KSTACK-8;

	ready(p);
}

void
segflush(void* p, ulong n) {
	cachedwbinvse(p,n);
	cacheiinvse(p,n);
}

void
idlehands(void) {
	m->inidle = 1;
	_idlehands();
}

void	exit(int) { return; }
void	halt(void) { spllo(); for(;;); }

void	fpinit(void) {}
void	FPsave(void*) {}
void	FPrestore(void*) {}
void	clockcheck(void) { return; }

