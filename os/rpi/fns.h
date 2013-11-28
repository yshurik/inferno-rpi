
#define KADDR(p)    ((void *)p)
#define PADDR(p)    ((ulong)p)
#define	coherence()		/* nothing needed for uniprocessor */
#define procsave(p)

int		waserror(void);
void    (*screenputs)(char*, int);

#include "../port/portfns.h"

