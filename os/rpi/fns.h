
#define KADDR(p)    ((void *)p)
#define PADDR(p)    ((ulong)p)
#define waserror()  (up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
#define	coherence()		/* nothing needed for uniprocessor */
#define procsave(p)		/* Save the mach part of the current */
						/* process state, no need for one cpu */

void	(*serwrite)(char*, int);
void    (*screenputs)(char*, int);

#include "../port/portfns.h"

void	pl011_putc(int);
void	pl011_puts(char *);
void	pl011_serputs(char *, int);
void	pl011_addr(void *a, int nl);

char *	trapname(int psr);
int		isvalid_va(void *v);
int		isvalid_wa(void *v);

