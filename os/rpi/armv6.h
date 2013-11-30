
/*
 * Program Status Registers
 */
#define PsrMusr		0x00000010	/* mode */
#define PsrMfiq		0x00000011
#define PsrMirq		0x00000012
#define PsrMsvc		0x00000013	/* `protected mode for OS' */
#define PsrMmon		0x00000016	/* `secure monitor' (trustzone hyper) */
#define PsrMabt		0x00000017
#define PsrMund		0x0000001B
#define PsrMsys		0x0000001F	/* `privileged user mode for OS' (trustzone) */
#define PsrMask		0x0000001F

#define PsrDfiq		0x00000040	/* disable FIQ interrupts */
#define PsrDirq		0x00000080	/* disable IRQ interrupts */

#define PsrV		0x10000000	/* overflow */
#define PsrC		0x20000000	/* carry/borrow/extend */
#define PsrZ		0x40000000	/* zero */
#define PsrN		0x80000000	/* negative/less than */


/* instruction decoding */
#define ISCPOP(op)        ((op) == 0xE || ((op) & ~1) == 0xC)
#define ISFPAOP(cp, op)        ((cp) == CpOFPA && ISCPOP(op))
#define ISVFPOP(cp, op)        (((cp) == CpDFP || (cp) == CpFP) && ISCPOP(op))

/*
 * Coprocessors
 */
#define CpOFPA      1                        /* ancient 7500 FPA */
#define CpFP        10          /* float FP, VFP cfg. */
#define CpDFP       11          /* double FP */
#define CpSC        15          /* System Control */

/*
 * Primary (CRn) CpSC registers.
 */
#define CpID        0           /* ID and cache type */
#define CpCONTROL   1           /* miscellaneous control */
#define CpTTB       2           /* Translation Table Base(s) */
#define CpDAC       3           /* Domain Access Control */
#define CpFSR       5           /* Fault Status */
#define CpFAR       6           /* Fault Address */
#define CpCACHE     7           /* cache/write buffer control */
#define CpTLB       8           /* TLB control */
#define CpCLD       9           /* L2 Cache Lockdown, op1==1 */
#define CpTLD       10          /* TLB Lockdown, with op2 */
#define CpVECS      12          /* vector bases, op1==0, Crm==0, op2s (cortex) */
#define CpPID       13          /* Process ID */
#define CpSPM       15          /* system performance monitor (arm1176) */

/*
 * CpCACHE Secondary (CRm) registers and opcode2 fields.  op1==0.
 * In ARM-speak, 'flush' means invalidate and 'clean' means writeback.
 */
#define CpCACHEintr 0           /* interrupt (op2==4) */
#define CpCACHEisi  1           /* inner-sharable I cache (v7) */
#define CpCACHEpaddr    4           /* 0: phys. addr (cortex) */
#define CpCACHEinvi 5           /* instruction, branch table */
#define CpCACHEinvd 6           /* data or unified */
#define CpCACHEinvu 7           /* unified (not on cortex) */
#define CpCACHEva2pa    8           /* va -> pa translation (cortex) */
#define CpCACHEwb   10          /* writeback */
#define CpCACHEinvdse   11          /* data or unified by mva */
#define CpCACHEwbi  14          /* writeback+invalidate */

#define CpCACHEall  0           /* entire (not for invd nor wb(i) on cortex) */
#define CpCACHEse   1           /* single entry */
#define CpCACHEsi   2           /* set/index (set/way) */
#define CpCACHEtest 3           /* test loop */
#define CpCACHEwait 4           /* wait (prefetch flush on cortex) */
#define CpCACHEdmbarr   5           /* wb only (cortex) */
#define CpCACHEflushbtc 6           /* flush branch-target cache (cortex) */
#define CpCACHEflushbtse 7          /* ⋯ or just one entry in it (cortex) */

/*
 * CpTLB Secondary (CRm) registers and opcode2 fields.
 */
#define CpTLBinvi	5			/* instruction */
#define CpTLBinvd	6			/* data */
#define CpTLBinvu	7			/* unified */

#define CpTLBinv	0			/* invalidate all */
#define CpTLBinvse	1			/* invalidate single entry */
#define CpTBLasid	2			/* by ASID (cortex) */

/*
 * CpSPM Secondary (CRm) registers and opcode2 fields.
 */
#define CpSPMctl    0           /* performance monitor control */
#define CpSPMcyc    1           /* cycle counter register */
#define CpSPMperf   12          /* various counters */

/*
 * CpCACHERANGE opcode2 fields for MCRR instruction (armv6)
 */
#define	CpCACHERANGEinvi	5		/* invalidate instruction  */
#define	CpCACHERANGEinvd	6		/* invalidate data */
#define CpCACHERANGEdwb		12		/* writeback */
#define CpCACHERANGEdwbi	14		/* writeback+invalidate */

/*
 * CpCONTROL op2 codes, op1==0, Crm==0.
 */
#define CpMainctl   0
#define CpAuxctl    1
#define CpCPaccess  2

/*
 * CpCONTROL: op1==0, CRm==0, op2==CpMainctl.
 * main control register.
 * cortex/armv7 has more ops and CRm values.
 */
#define CpCmmu      0x00000001  /* M: MMU enable */
#define CpCalign    0x00000002  /* A: alignment fault enable */
#define CpCdcache   0x00000004  /* C: data cache on */
#define CpCsbo (3<<22|1<<18|1<<16|017<<3)   /* must be 1 (armv7) */
#define CpCsbz (CpCtre|1<<26|CpCve|1<<15|7<<7)  /* must be 0 (armv7) */
#define CpCsw       (1<<10)     /* SW: SWP(B) enable (deprecated in v7) */
#define CpCpredict  0x00000800  /* Z: branch prediction (armv7) */
#define CpCicache   0x00001000  /* I: instruction cache on */
#define CpChv       0x00002000  /* V: high vectors */
#define CpCrr       (1<<14) /* RR: round robin vs random cache replacement */
#define CpCha       (1<<17)     /* HA: hw access flag enable */
#define CpCdz       (1<<19)     /* DZ: divide by zero fault enable */
#define CpCfi       (1<<21)     /* FI: fast intrs */
#define CpCve       (1<<24)     /* VE: intr vectors enable */
#define CpCee       (1<<25)     /* EE: exception endianness */
#define CpCnmfi     (1<<27)     /* NMFI: non-maskable fast intrs. */
#define CpCtre      (1<<28)     /* TRE: TEX remap enable */
#define CpCafe      (1<<29)     /* AFE: access flag (ttb) enable */

//#define PADDR(va)	(PHYSDRAM | ((va) & ~KTZERO))

/*
 * MMU page table entries.
 * Mbz (0x10) bit is implementation-defined and must be 0 on the cortex.
 */
#define Mbz			(0<<4)
#define Fault		0x00000000		/* L[12] pte: unmapped */

#define Coarse		(Mbz|1)			/* L1 */
#define Section		(Mbz|2)			/* L1 1MB */
#define Fine		(Mbz|3)			/* L1 */

#define Large		0x00000001		/* L2 64KB */
#define Small		0x00000002		/* L2 4KB */
#define Tiny		0x00000003		/* L2 1KB: not in v7 */
#define Buffered	0x00000004		/* L[12]: write-back not -thru */
#define Cached		0x00000008		/* L[12] */
#define Dom0		0

#define Noaccess	0			/* AP, DAC */
#define Krw			1			/* AP */
/* armv7 deprecates AP[2] == 1 & AP[1:0] == 2 (Uro), prefers 3 (new in v7) */
#define Uro			2			/* AP */
#define Urw			3			/* AP */
#define Client		1			/* DAC */
#define Manager		3			/* DAC */

#define F(v, o, w)	(((v) & ((1<<(w))-1))<<(o))
#define AP(n, v)	F((v), ((n)*2)+4, 2)
#define L1AP(ap)	(AP(3, (ap)))
#define L2AP(ap) (AP(3, (ap))|AP(2, (ap))|AP(1, (ap))|AP(0, (ap))) /* pre-armv7 */
#define DAC(n, v)	F((v), (n)*2, 2)

/*
 * For multi-bit fields use FIELD(v, o, w) where 'v' is the value
 * of the bit-field of width 'w' with LSb at bit offset 'o'.
 */
#define FIELD(v, o, w)	(((v) & ((1<<(w))-1))<<(o))

#define FCLR(d, o, w)	((d) & ~(((1<<(w))-1)<<(o)))
#define FEXT(d, o, w)	(((d)>>(o)) & ((1<<(w))-1))
#define FINS(d, o, w, v) (FCLR((d), (o), (w))|FIELD((v), (o), (w)))
#define FSET(d, o, w)	((d)|(((1<<(w))-1)<<(o)))

#define FMASK(o, w)	(((1<<(w))-1)<<(o))

#define ISB \
	MOVW	$0, R0; \
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEinvi), CpCACHEwait

#define DSB \
	MOVW	$0, R0; \
	MCR	CpSC, 0, R0, C(CpCACHE), C(CpCACHEwb), CpCACHEwait

#define BARRIERS ISB; DSB

#define MCRR(coproc, op, rd, rn, crm) \
		WORD $(0xec400000|(rn)<<16|(rd)<<12|(coproc)<<8|(op)<<4|(crm))

#define LVECTORS	0x00000000
#define HVECTORS	0xffff0000
