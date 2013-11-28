
#include "mem.h"
#include "armv6.h"

TEXT setr13(SB), $-4
	MOVW	4(FP), R1
	MOVW	CPSR, R2
	BIC		$PsrMask, R2, R3
	ORR		R0, R3
	MOVW	R3, CPSR		/* switch to new mode */
	MOVW	SP, R0			/* return old sp */
	MOVW	R1, SP			/* install new one */
	MOVW	R2, CPSR		/* switch back to old mode */
	RET

TEXT vectors(SB), $-4
	MOVW    0x18(PC), PC	/* reset */
	MOVW    0x18(PC), PC	/* undefined */
	MOVW    0x18(PC), PC	/* SWI */
	MOVW    0x18(PC), PC	/* prefetch abort */
	MOVW    0x18(PC), PC	/* data abort */
	MOVW    0x18(PC), PC	/* reserved */
	MOVW    0x18(PC), PC	/* IRQ */
	MOVW    0x18(PC), PC	/* FIQ */

TEXT vtable(SB), $-4
	WORD	$_vsvc(SB)		/* reset, in svc mode already */
	WORD	$_vund(SB)		/* undefined, switch to svc mode */
	WORD	$_vsvc(SB)		/* swi, in svc mode already */
	WORD	$_vpab(SB)		/* prefetch abort, switch to svc mode */
	WORD	$_vdab(SB)		/* data abort, switch to svc mode */
	WORD	$_vsvc(SB)		/* reserved */
	WORD	$_virq(SB)		/* IRQ, switch to svc mode */
	WORD	$_vfiq(SB)		/* FIQ, switch to svc mode */

TEXT _vund(SB), $-4
	MOVM.DB	[R0-R3], (SP)
	MOVW	$PsrMund, R0
	B		_vswitch

TEXT _vsvc(SB), $-4
	MOVW.W	R14, -4(SP)
	MOVW	CPSR, R14
	MOVW.W	R14, -4(SP)
	BIC		$PsrMask, R14
	ORR		$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW	R14, CPSR
	MOVW	$PsrMsvc, R14
	MOVW.W	R14, -4(SP)
	B		_vsaveu

TEXT _vpab(SB), $-4
	MOVM.DB	[R0-R3], (R13)
	MOVW	$PsrMabt, R0
	B		_vswitch

TEXT _vdab(SB), $-4
	MOVM.DB	[R0-R3], (R13)
	MOVW	$(PsrMabt+1), R0
	B		_vswitch

TEXT _vfiq(SB), $-4				/* FIQ */
	MOVM.DB	[R0-R3], (R13)
	MOVW	$PsrMfiq, R0
	B		_vswitch

TEXT _virq(SB), $-4				/* IRQ */
	MOVM.DB	[R0-R3], (R13)
	MOVW	$PsrMirq, R0

_vswitch:						/* switch to svc mode */
	MOVW		SPSR,	R1		/* state of cpu, cpsr */
	MOVW		R14,	R2		/* return code */
	MOVW		SP,		R3		/* stack */

	MOVW		CPSR,	R14
	BIC			$PsrMask, R14
	ORR			$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW		R14, CPSR		/* switch! * /

	MOVW		R0, R0				/* gratuitous noop */

	MOVM.DB.W	[R0-R2], (SP)	/* set ureg->{type, psr, pc}; SP points to ureg->type  */
	MOVW		R3, -12(SP)
	MOVM.IA		(R3), [R0-R3]	/* restore [R0-R3] from previous mode's stack */

_vsaveu:
	MOVW.W		R11, -4(SP)		/* save link */

	SUB			$8, SP
	MOVM.DB.W	[R0-R12], (SP)

	MOVW		$setR12(SB), R12	/* Make sure we've got the kernel's SB loaded */
	MOVW		SP, R0				/* first arg is pointer to ureg */
	SUB			$(4*2), SP			/* space for argument+link (for debugger) */
	MOVW		$0xdeaddead, R11	/* marker */
	BL			trap(SB)

_vrfe:								/* Restore Regs */
	MOVW		CPSR, R0			/* splhi on return */
	ORR			$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	ADD			$(8+4*15), SP		/* [r0-R14]+argument+link */
	MOVW		(SP), R14			/* restore link */
	MOVW		8(SP), R0
	MOVW		R0, SPSR
	MOVM.DB.S   (SP), [R0-R14]		/* restore user registers */
	MOVW		R0, R0				/* gratuitous nop */
	ADD			$12, SP				/* skip saved link+type+SPSR*/
	RFE								/* MOVM.IA.S.W (SP), [PC] */
