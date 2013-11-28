typedef unsigned int    u32int;
#define IOBASE          0x20000000      /* base of io registers */
#define PL011REGS       (IOBASE+0x201000)
#define UART_PL01x_FR_TXFF  0x20

void
pl011_putc(int c)
{
	u32int *ap;
	ap = (u32int*)PL011REGS;
	/* Wait until there is space in the FIFO */
	while (ap[0x18>>2] & UART_PL01x_FR_TXFF)
		;

	/* Send the character */
	ap[0] = c;

	/* Wait until there is space in the FIFO */
	while (ap[0x18>>2] & UART_PL01x_FR_TXFF)
		;
}

void
pl011_puts(char *s) {
	while(*s != 0) {
		if (*s == '\n')
			pl011_putc('\r');
		pl011_putc(*s++);
	}
}

void 
main() {
	char * s = "Hello world!\n";
	pl011_puts(s);
	for (;;);
}

#include "u.h"
#include "../port/lib.h"
#include "dat.h"
#include "mem.h"

Conf conf;
Mach *m = (Mach*)MACHADDR;
Proc *up = 0;

#include "../port/uart.h"
PhysUart* physuart[1];

int		waserror(void) { return 0; }
int		splhi(void) { return 0; }
void	splx(int) { return; }
int		spllo(void) { return 0; } 
void	splxpc(int) { return; }
int		islo(void) { return 0; }
int		setlabel(Label*) { return 0; }
void	gotolabel(Label*) { return; }
ulong	getcallerpc(void*) { return 0; }
int		segflush(void*, ulong) { return 0; }
void	idlehands(void) { return; }
void 	kprocchild(Proc *p, void (*func)(void*), void *arg) { return; }
ulong	_tas(ulong*) { return 0; }
ulong	_div(ulong*) { return 0; }
ulong	_divu(ulong*) { return 0; }
ulong	_mod(ulong*) { return 0; }
ulong	_modu(ulong*) { return 0; }

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
