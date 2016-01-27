
#include "u.h"
#include "../port/lib.h"
#include "io.h"
#include "dat.h"
#include "fns.h"

#define IOBASE                 0x20000000              /* base of io regs */
#define INTREGS                        (IOBASE+0x00B200)
#define PL011REGS              (IOBASE+0x201000)

#define UART_PL01x_FR_RXFE  0x10
#define UART_PL01x_FR_TXFF     0x20

static void pl011_clock(void);
extern Queue*  kbdq;

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
pl011_addr(void *a, int nl)
{
	int i;
	unsigned char *ca = (unsigned char *)&a;
	unsigned char h,l;

	for (i=3;i>=0;--i) {
		h = ca[i]/16;
		l = ca[i]%16;
		pl011_putc(h<10 ? h+0x30 : h-10+0x41);
		pl011_putc(l<10 ? l+0x30 : l-10+0x41);
	}
	if (nl) {
		pl011_putc(13);
		pl011_putc(10);
	}
}
