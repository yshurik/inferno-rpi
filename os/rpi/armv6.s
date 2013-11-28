
#include "mem.h"
#include "armv6.h"

TEXT setlabel(SB), $-4
	MOVW    R13, 0(R0)
	MOVW    R14, 4(R0)
	MOVW    $0, R0
	RET

TEXT gotolabel(SB), $-4
	MOVW    0(R0), R13
	MOVW    4(R0), R14
	MOVW    $1, R0
	RET

TEXT getcallerpc(SB), $-4
	MOVW    0(SP), R0
	RET

TEXT splhi(SB), $-4
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)   /* m->splpc */
	MOVW	CPSR, R0
	ORR		$(PsrDirq), R0, R1
	MOVW	R1, CPSR
	RET

TEXT spllo(SB), $-4
	MOVW	CPSR, R0
	BIC		$(PsrDirq|PsrDfiq), R0, R1
	MOVW	R1, CPSR
	RET

TEXT splx(SB), $-4
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)   /* m->splpc */
TEXT splxpc(SB), $-4
	MOVW	R0, R1
	MOVW	CPSR, R0
	MOVW	R1, CPSR
	RET

TEXT islo(SB), $-4
	MOVW	CPSR, R0
	AND		$(PsrDirq), R0
	EOR		$(PsrDirq), R0
	RET

