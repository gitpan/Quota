/*
 *   Configuration example for BSDI
 *
 *   Ported to BSDI  by Jim Hribnak (hribnak@nucleus.com) Aug 28 1997
 *   with the help of the original author Tom Zoerner 
 *   (Tom.Zoerner@informatik.uni-erlangen.de)
 */

/*
 *   RPC yet unsupported.
 *   If you want RPC, #undef NO_RPC below.
 *   If you get it to work, please mail me    -tom
 */

/*   See hints/none.h for a complete list of options with explanations */

#include <sys/param.h>
#include <sys/mount.h>
#include <fstab.h>
#include <ufs/ufs/quota.h>

#include <rpc/rpc.h>
#include <rpc/pmap_prot.h>
#include <rpc/svc.h>
#include "include/rquota.h"

#include <sys/socket.h>
#include <netdb.h>

#include <stdio.h>

#define Q_DIV / 2
#define Q_MUL * 2
#define DEV_QBSIZE DEV_BSIZE
#define Q_CTL_V2
#define Q_SETQLIM Q_SETQUOTA
#define CADR (caddr_t)

#define NO_RPC

#define MY_XDR

#define NO_MNTENT
 
#define GQR_STATUS gqr_status
#define GQR_RQUOTA gqr_rquota

#define QS_BHARD dqb_bhardlimit
#define QS_BSOFT dqb_bsoftlimit
#define QS_BCUR  dqb_curblocks
#define QS_FHARD dqb_ihardlimit
#define QS_FSOFT dqb_isoftlimit
#define QS_FCUR  dqb_curinodes
#define QS_BTIME dqb_btime
#define QS_FTIME dqb_itime

