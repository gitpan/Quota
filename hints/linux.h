/*
 *   Configuration for Linux 2.0.22 and later
 *
 *   For AFS support look at the end of this file
 */

/*   See hints/none.h for a complete list of options with explanations */

#include <sys/param.h>
#include <sys/types.h>
/* #include <linux/types.h> */
/* asm/types.h is needed only on some systems (Debian 2.0, RedHat)
   if you don't have it you should remove the following line */
#include <asm/types.h>
#include <linux/quota.h>
#include <sys/syscall.h>
#include <mntent.h>

#include <rpc/rpc.h>
#include <rpc/pmap_prot.h>
#include <rpcsvc/rquota.h>
/* #include "include/rquota.h" */
#include <sys/socket.h>
#include <netdb.h>

#include <strings.h>
#include <stdio.h>

#define Q_DIV
#define Q_MUL
#define DEV_QBSIZE 1024

#define Q_CTL_V3
#define CADR (caddr_t)

#define MY_XDR

#define MNTENT mntent

#define GQR_STATUS status
#define GQR_RQUOTA getquota_rslt_u.gqr_rquota

#define QS_BHARD dqb_bhardlimit
#define QS_BSOFT dqb_bsoftlimit
#define QS_BCUR  dqb_curblocks
#define QS_FHARD dqb_ihardlimit
#define QS_FSOFT dqb_isoftlimit
#define QS_FCUR  dqb_curinodes
#define QS_BTIME dqb_btime
#define QS_FTIME dqb_itime

#define LINUX_RQUOTAD_BUG


/*
 *  If you have AFS (arla) uncomment the following define and MAKE lines
 */
/* #define AFSQUOTA */

/* MakeMaker parameters - do not remove!
#MAKE AFSHOME=/products/security/athena
#MAKE OBJ=afsquota.o afssys.o
## Linux does not record LD_RUN_PATH within DLOs, so we do without shlibs
## and extract the required object from the lib to link statically
#MAKE ARXLIBOBJ=$(AFSHOME)/lib/libkafs.a afssys.o
*/
