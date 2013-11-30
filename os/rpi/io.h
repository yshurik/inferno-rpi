
#define IOBASE			0x20000000		/* base of io regs */
#define INTREGS			(IOBASE+0x00B200)
#define POWERREGS		(IOBASE+0x100000)
#define PL011REGS		(IOBASE+0x201000)

#define UART_PL01x_FR_RXFE  0x10
#define UART_PL01x_FR_TXFF	0x20

typedef struct Intregs Intregs;

/* interrupt control registers */
struct Intregs {
	u32int  ARMpending;
	u32int  GPUpending[2];
	u32int  FIQctl;
	u32int  GPUenable[2];
	u32int  ARMenable;
	u32int  GPUdisable[2];
	u32int  ARMdisable;
};

enum {
	IRQtimer0	= 0,
	IRQtimer1	= 1,
	IRQtimer2	= 2,
	IRQtimer3	= 3,
	IRQclock	= IRQtimer3,
	IRQusb		= 9,
	IRQdma0		= 16,
#define IRQDMA(chan)	(IRQdma0+(chan))
	IRQaux		= 29,
	IRQmmc		= 62,
	IRQbasic	= 64,
	IRQtimerArm	= IRQbasic + 0,
	IRQfiq		= IRQusb,	/* only one source can be FIQ */
	DmaD2M		= 0,		/* device to memory */
	DmaM2D		= 1,		/* memory to device */
	DmaM2M		= 2,		/* memory to memory */
	DmaChanEmmc	= 4,		/* can only use 2-5, 11-12 */
	DmaDevEmmc	= 11,

	PowerSd		= 0,
	PowerUart0,
	PowerUart1,
	PowerUsb,
	PowerI2c0,
	PowerI2c1,
	PowerI2c2,
	PowerSpi,
	PowerCcp2tx,

	ClkEmmc		= 1,
	ClkUart,
	ClkArm,
	ClkCore,
	ClkV3d,
	ClkH264,
	ClkIsp,
	ClkSdram,
	ClkPixel,
	ClkPwm,
};



