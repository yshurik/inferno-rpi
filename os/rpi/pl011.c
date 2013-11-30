
#include "u.h"
#include "../port/lib.h"
#include "io.h"
#include "dat.h"
#include "fns.h"

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

int 
pl011_getc(void)
{
	int c;
	u32int *ap;
	ap = (u32int*)PL011REGS;

	/* Wait until there is data in the FIFO */
	while (ap[0x18>>2] & UART_PL01x_FR_RXFE)
		;

	c = ap[0];
	return c;
}

int
pl011_tstc(void)
{
	u32int *ap;
	ap = (u32int*)PL011REGS;

	/* Check if there is data in the FIFO */
	return !(ap[0x18>>2] & UART_PL01x_FR_RXFE);
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
pl011_serputs(char *s, int n) {
	while(*s != 0 && n-- >=0) {
		if (*s == '\n')
			pl011_putc('\r');
		pl011_putc(*s++);
	}
}

void
pl011init(void)
{
	if(kbdq == nil)
		kbdq = qopen(4*1024, 0, 0, 0);
				    
	/*
	 * at 115200 baud, the 1024 char buffer takes 56 ms to process,
	 * processing it every 22 ms should be fine
	 */
	addclock0link(pl011_clock, 22);
}

static void
pl011_clock(void)
{
	char c;
	int i;
	if (pl011_tstc()) {
		c = pl011_getc();
		if (c == 13) {
			pl011_putc('\r');
			pl011_putc('\n');
			kbdputc(kbdq,'\r');
			kbdputc(kbdq,'\n');
			return;
		}
		pl011_putc(c);
		kbdputc(kbdq,c);
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
