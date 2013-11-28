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
