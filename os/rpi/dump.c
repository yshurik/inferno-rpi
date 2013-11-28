#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "ureg.h"
#include "armv6.h"

void
dumplongs(char *msg, ulong *v, int n)
{
	int i, l;

	l = 0;
	iprint("%s at %.8p: ", msg, v);
	for(i=0; i<n; i++){
		if(l >= 4){
			iprint("\n    %.8p: ", v);
			l = 0;
		}
		if(isvalid_va(v)){
			iprint(" %.8lux", *v++);
			l++;
		}else{
			iprint(" invalid");
			break;
		}
	}
	iprint("\n");
}

static void
_dumpstack(Ureg *ureg)
{
	ulong *v, *l;
	ulong inst;
	ulong *estack;
	int i;

	l = (ulong*)(ureg+1);
	if(!isvalid_wa(l)){
		iprint("invalid ureg/stack: %.8p\n", l);
		return;
	}
	print("ktrace/kernel/path %.8ux %.8ux %.8ux\n", ureg->pc, ureg->sp, ureg->r14);
	if(up != nil && l >= (ulong*)up->kstack && l <= (ulong*)(up->kstack+KSTACK-4))
		estack = (ulong*)(up->kstack+KSTACK);
	else if(l >= (ulong*)m->stack && l <= (ulong*)((ulong)m+BY2PG-4))
		estack = (ulong*)((ulong)m+BY2PG-4);
	else{
		iprint("unknown stack\n");
		return;
	}
	i = 0;
	for(; l<estack; l++) {
		if(!isvalid_wa(l)) {
			iprint("invalid(%8.8p)", l);
			break;
		}
		v = (ulong*)*l;
		if(isvalid_wa(v)) {
			inst = v[-1];
			if((inst & 0x0ff0f000) == 0x0280f000 &&
				 (*(v-2) & 0x0ffff000) == 0x028fe000    ||
				(inst & 0x0f000000) == 0x0b000000) {
				iprint("%8.8p=%8.8lux ", l, v);
				i++;
			}
		}
		if(i == 4){
			iprint("\n");
			i = 0;
		}
	}
	if(i)
		print("\n");
}

/*
 * Fill in enough of Ureg to get a stack trace, and call a function.
 * Used by debugging interface rdb.
 */
void
callwithureg(void (*fn)(Ureg*))
{
	Ureg ureg;
	ureg.pc = getcallerpc(&fn);
	ureg.sp = (ulong)&fn;
	ureg.r14 = 0;
	fn(&ureg);
}

void
dumpstack(void)
{
	callwithureg(_dumpstack);
}

void
dumparound(uint addr)
{
	uint addr0 = (addr/16)*16;
	int a_row, a_col;
	uchar ch, *cha;
	uint c;
	/* +-32 bytes to print */
	print("%8.8uX:\n", addr0 +(-2)*16);
	for (a_col = 0; a_col<16; ++a_col) {
		print("|%.2uX", a_col);
	}
	print("\n");

	for (a_row = -2; a_row < 3; ++a_row) {
		for (a_col = 0; a_col<16; ++a_col) {
			cha = (uchar *)(addr0 +a_row*16+a_col);
			ch = *cha;
			c = ch;
			if (cha == (uchar *)addr)
				print(">%2.2uX", c);
			else print(" %2.2uX", c);
		}
		print("\n");
	}
	print("\n");
}

void
dumpregs(Ureg* ureg)
{
	print("TRAP: %s", trapname(ureg->type));
	if((ureg->psr & PsrMask) != PsrMsvc)
		print(" in %s", trapname(ureg->psr));
	print("\n");
	print("PSR %8.8uX type %2.2uX PC %8.8uX LINK %8.8uX\n",
		ureg->psr, ureg->type, ureg->pc, ureg->link);
	print("R14 %8.8uX R13 %8.8uX R12 %8.8uX R11 %8.8uX R10 %8.8uX\n",
		ureg->r14, ureg->r13, ureg->r12, ureg->r11, ureg->r10);
	print("R9  %8.8uX R8  %8.8uX R7  %8.8uX R6  %8.8uX R5  %8.8uX\n",
		ureg->r9, ureg->r8, ureg->r7, ureg->r6, ureg->r5);
	print("R4  %8.8uX R3  %8.8uX R2  %8.8uX R1  %8.8uX R0  %8.8uX\n",
		ureg->r4, ureg->r3, ureg->r2, ureg->r1, ureg->r0);
	print("Stack is at: %8.8luX\n", ureg);
	print("PC %8.8lux LINK %8.8lux\n", (ulong)ureg->pc, (ulong)ureg->link);

	if(up)
		print("Process stack:  %8.8lux-%8.8lux\n",
			up->kstack, up->kstack+KSTACK-4);
	else
		print("System stack: %8.8lux-%8.8lux\n",
			(ulong)(m+1), (ulong)m+BY2PG-4);
	dumplongs("stack", (ulong *)(ureg + 1), 16);
	_dumpstack(ureg);
	dumparound(ureg->pc);
}
