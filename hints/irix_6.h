/*
 *   Configuration for 6.2 - 6.4
 *   (the only difference to IRIX 5 is XFS support)
 */

#include <unistd.h>
#include <stdio.h>

#include <sys/param.h>
#include <sys/types.h>
#include <sys/quota.h>
#include <mntent.h>

#include <rpc/rpc.h>
#include <rpc/pmap_prot.h>
#include <rpcsvc/rquota.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>

#define Q_DIV
#define Q_MUL
#define DEV_QBSIZE DEV_BSIZE
#define CADR (caddr_t)

#define MNTENT mntent

#define GQR_STATUS gqr_status
#define GQR_RQUOTA gqr_rquota

#define QS_BHARD dqb_bhardlimit
#define QS_BSOFT dqb_bsoftlimit
#define QS_BCUR  dqb_curblocks
#define QS_FHARD dqb_fhardlimit
#define QS_FSOFT dqb_fsoftlimit
#define QS_FCUR  dqb_curfiles
#define QS_BTIME dqb_btimelimit
#define QS_FTIME dqb_ftimelimit

/* for IRIX 6.2 you MUST install the latest xfs patch sets! */
#define IRIX_XFS
