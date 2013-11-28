
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

TEXT getsp(SB), $-4
	MOVW    SP, R0
	RET

TEXT getpc(SB), $-4
	MOVW    R14, R0
	RET

TEXT getsc(SB), $-4
	MRC     CpSC, 0, R0, C(CpCONTROL), C(0), CpMainctl
	RET

TEXT getcpsr(SB), $-4
	MOVW	CPSR, R0
	RET

TEXT getspsr(SB), $-4
	MOVW	SPSR, R0
	RET

TEXT coherence(SB), $-4
	BARRIERS
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

TEXT _tas(SB), $-4
	MOVW    R0, R1
	MOVW    $0xDEADDEAD, R2
	SWPW    R2, (R1), R0
	RET

TEXT getcpuid(SB), $-4
	MRC		CpSC, 0, R0, C(CpID), C(0)
	RET

TEXT lcycles(SB), $-4
	MRC CpSC, 0, R0, C(CpSPM), C(CpSPMperf), CpSPMcyc
	RET

