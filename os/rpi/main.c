
#include "u.h"
#include "../port/lib.h"
#include "dat.h"
#include "mem.h"
#include "fns.h"

#include "../port/uart.h"
PhysUart* physuart[1];

Conf conf;
Mach *m = (Mach*)MACHADDR;
Proc *up = 0;

extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;

void
confinit(void)
{
	ulong base;
	conf.topofmem = 128*MB;

	base = PGROUND((ulong)end);
	conf.base0 = base;

	conf.npage1 = 0;
	conf.npage0 = (conf.topofmem - base)/BY2PG;
	conf.npage = conf.npage0 + conf.npage1;
	conf.ialloc = (((conf.npage*(main_pool_pcnt))/100)/2)*BY2PG;

	conf.nproc = 100 + ((conf.npage*BY2PG)/MB)*5;
	conf.nmach = 1;

	print("Conf: top=%lud, npage0=%lud, ialloc=%lud, nproc=%lud\n",
			conf.topofmem, conf.npage0,
			conf.ialloc, conf.nproc);
}

static void
poolsizeinit(void)
{
	ulong nb;
	nb = conf.npage*BY2PG;
	poolsize(mainmem, (nb*main_pool_pcnt)/100, 0);
	poolsize(heapmem, (nb*heap_pool_pcnt)/100, 0);
	poolsize(imagmem, (nb*image_pool_pcnt)/100, 1);
}

void
main() {
	pl011_puts("Entered main() at ");
	pl011_addr(&main, 0);
	pl011_puts(" with SP=");
	pl011_addr((void *)getsp(), 1.);

	pl011_puts("Clearing Mach:  ");
	memset(m, 0, sizeof(Mach));
	pl011_addr((char *)m,		0); pl011_puts("-");
	pl011_addr((char *)(m+1),	1);

	pl011_puts("Clearing edata: ");
	memset(edata, 0, end-edata);
	pl011_addr((char *)&edata,	0); pl011_puts("-");
	pl011_addr((char *)&end,	1);

	conf.nmach = 1;
	serwrite = &pl011_serputs;

	confinit();
	xinit();
	poolinit();
	poolsizeinit();

	pl011_puts("to inifinite loop\n\n");

	for (;;);
}

void	segflush(void*, ulong) { return; }
void	idlehands(void) { return; }
void 	kprocchild(Proc *p, void (*func)(void*), void *arg) { return; }

void	setpanic(void) { return; }
void	dumpstack(void) { return; }
void	exit(int) { return; }
void	reboot(void) { return; }
void	halt(void) { return; }

Timer*	addclock0link(void (*)(void), int) { return 0; }
void	clockcheck(void) { return; }

void	fpinit(void) {}
void	FPsave(void*) {}
void	FPrestore(void*) {}
