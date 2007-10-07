#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#include "myconfig.h"

#ifdef SFIO_VERSION
#include "stdio_wrap.h"
#else
#define std_fopen fopen
#define std_fclose fclose
#endif

#ifdef AFSQUOTA
#include "include/afsquota.h"
#endif

#ifdef SOLARIS_VXFS
#include "include/vxquotactl.h"
#endif

#ifndef AIX
#ifndef NO_MNTENT
FILE *mtab = NULL;
#else
struct statfs *mntp, *mtab = NULL;
int mtab_size = 0;
#endif
#else /* AIX */
static struct vmount *mtab = NULL;
static aix_mtab_idx, aix_mtab_count;
#endif

#define RPC_DEFAULT_TIMEOUT 4000

#ifndef NO_RPC
static struct
{
  char            use_tcp;
  unsigned short  port;
  unsigned        timeout;
} quota_rpc_cfg = {FALSE, 0, 4000};

static struct
{
    int           uid;
    int           gid;
    char          hostname[MAX_MACHINE_NAME + 1];
} quota_rpc_auth = {-1, -1, {0} };

/*
 * fetch quotas from remote host
 */

int
callaurpc(host, prognum, versnum, procnum, inproc, in, outproc, out)
  char *host;
  xdrproc_t inproc, outproc;
  char *in, *out;
{
  struct sockaddr_in remaddr;
  struct hostent *hp;
  enum clnt_stat clnt_stat;
  struct timeval rep_time, timeout;
  CLIENT *client;
  int socket = RPC_ANYSOCK;

  /*
   *  Get IP address; by default the port is determined via remote
   *  portmap daemon; different ports and protocols can be configured
   */
  hp = gethostbyname(host);
  if (hp == NULL)
    return ((int) RPC_UNKNOWNHOST);

  rep_time.tv_sec = quota_rpc_cfg.timeout / 1000;
  rep_time.tv_usec = (quota_rpc_cfg.timeout % 1000) * 1000;
  memcpy((char *)&remaddr.sin_addr, (char *)hp->h_addr, hp->h_length);
  remaddr.sin_family = AF_INET;
  remaddr.sin_port = htons(quota_rpc_cfg.port);

  /*
   *  Create client RPC handle
   */
  client = NULL;
  if (!quota_rpc_cfg.use_tcp) {
    client = (CLIENT *)clntudp_create(&remaddr, prognum, 
                                      versnum, rep_time, &socket);
  }
  else {
    client = (CLIENT *)clnttcp_create(&remaddr, prognum, 
                                      versnum, &socket, 0, 0);
  }

  if (client == NULL)
    return ((int) rpc_createerr.cf_stat);
  
  /* 
   *  Create an authentication handle
   */
  if ((quota_rpc_auth.uid != -1) && (quota_rpc_auth.gid != -1)) {
    client->cl_auth = authunix_create(quota_rpc_auth.hostname,
                                      quota_rpc_auth.uid,
                                      quota_rpc_auth.gid, 0, 0);
  }
  else {
    client->cl_auth = authunix_create_default();
  }

  /*
   *  Call remote server
   */
  timeout.tv_sec = quota_rpc_cfg.timeout / 1000;
  timeout.tv_usec = (quota_rpc_cfg.timeout % 1000) * 1000;
  clnt_stat = clnt_call(client, procnum,
                        inproc, in, outproc, out, timeout);
  if (client) clnt_destroy(client);

  return ((int) clnt_stat);
}

int
getnfsquota(hostp, fsnamep, uid, dqp)
  char *hostp, *fsnamep;
  int uid;
  struct dqblk *dqp;
{
  struct getquota_args gq_args;
  struct getquota_rslt gq_rslt;

  gq_args.gqa_pathp = fsnamep;
  gq_args.gqa_uid = uid;
  if (callaurpc(hostp, RQUOTAPROG, RQUOTAVERS, RQUOTAPROC_GETQUOTA,
      xdr_getquota_args, &gq_args, xdr_getquota_rslt, &gq_rslt) != 0) {
    return (-1);
  }
  switch (gq_rslt.GQR_STATUS) {
  case Q_OK:
    {
      struct timeval tv;

      gettimeofday(&tv, NULL);
#ifdef LINUX_RQUOTAD_BUG
      /* Since Linux reports a bogus block size value (4k), we must not
       * use it. Thankfully Linux at least always uses 1k block sizes
       * for quota reports, so we just leave away all conversions.
       * If you have a mixed environment, you have a problem though.
       * Complain to the Linux authors or apply my patch (see INSTALL)
       */
      dqp->QS_BHARD = gq_rslt.GQR_RQUOTA.rq_bhardlimit;
      dqp->QS_BSOFT = gq_rslt.GQR_RQUOTA.rq_bsoftlimit;
      dqp->QS_BCUR = gq_rslt.GQR_RQUOTA.rq_curblocks;
#else /* not buggy */
      if (gq_rslt.GQR_RQUOTA.rq_bsize >= DEV_QBSIZE) {
	/* we rely on the fact that block sizes are always powers of 2 */
	/* so the conversion factor will never be a fraction */
        int qb_fac = gq_rslt.GQR_RQUOTA.rq_bsize / DEV_QBSIZE;
	dqp->QS_BHARD = gq_rslt.GQR_RQUOTA.rq_bhardlimit * qb_fac;
	dqp->QS_BSOFT = gq_rslt.GQR_RQUOTA.rq_bsoftlimit * qb_fac;
	dqp->QS_BCUR = gq_rslt.GQR_RQUOTA.rq_curblocks * qb_fac;
      }
      else {
        int qb_fac = DEV_QBSIZE / gq_rslt.GQR_RQUOTA.rq_bsize;
	dqp->QS_BHARD = gq_rslt.GQR_RQUOTA.rq_bhardlimit / qb_fac;
	dqp->QS_BSOFT = gq_rslt.GQR_RQUOTA.rq_bsoftlimit / qb_fac;
	dqp->QS_BCUR = gq_rslt.GQR_RQUOTA.rq_curblocks / qb_fac;
      }
#endif /* LINUX_RQUOTAD_BUG */
      dqp->QS_FHARD = gq_rslt.GQR_RQUOTA.rq_fhardlimit;
      dqp->QS_FSOFT = gq_rslt.GQR_RQUOTA.rq_fsoftlimit;
      dqp->QS_FCUR = gq_rslt.GQR_RQUOTA.rq_curfiles;

      /* if time is given relative to actual time, add actual time */
      /* Note: all systems except Linux return relative times */
      if (gq_rslt.GQR_RQUOTA.rq_btimeleft == 0)
        dqp->QS_BTIME = 0;
      else if (gq_rslt.GQR_RQUOTA.rq_btimeleft + 10*365*24*60*60 < tv.tv_sec)
        dqp->QS_BTIME = tv.tv_sec + gq_rslt.GQR_RQUOTA.rq_btimeleft;
      else
        dqp->QS_BTIME = gq_rslt.GQR_RQUOTA.rq_btimeleft;

      if (gq_rslt.GQR_RQUOTA.rq_ftimeleft == 0)
        dqp->QS_FTIME = 0;
      else if (gq_rslt.GQR_RQUOTA.rq_ftimeleft + 10*365*24*60*60 < tv.tv_sec)
        dqp->QS_FTIME = tv.tv_sec + gq_rslt.GQR_RQUOTA.rq_ftimeleft;
      else
        dqp->QS_FTIME = gq_rslt.GQR_RQUOTA.rq_ftimeleft;

      if(dqp->QS_BHARD==0 && dqp->QS_BSOFT==0 &&
         dqp->QS_FHARD==0 && dqp->QS_FSOFT==0) {
        errno = ESRCH;
	return(-1);
      }
      return (0);
    }

  case Q_NOQUOTA:
    errno = ESRCH;
    break;

  case Q_EPERM:
    errno = EPERM;
    break;

  default:
    errno = EINVAL;
    break;
  }
  return (-1);
}

#ifdef MY_XDR

struct xdr_discrim gq_des[2] = {
  { (int)Q_OK, (xdrproc_t)xdr_rquota },
  { 0, NULL }
};

bool_t
xdr_getquota_args(xdrs, gqp)
XDR *xdrs;
struct getquota_args *gqp;
{
  return (xdr_string(xdrs, &gqp->gqa_pathp, 1024) &&
          xdr_int(xdrs, &gqp->gqa_uid));
}

bool_t
xdr_getquota_rslt(xdrs, gqp)
XDR *xdrs;
struct getquota_rslt *gqp;
{
  return (xdr_union(xdrs,
    (int *) &gqp->GQR_STATUS, (char *) &gqp->GQR_RQUOTA,
    gq_des, (xdrproc_t) xdr_void));
}

bool_t
xdr_rquota(xdrs, rqp)
XDR *xdrs;
struct rquota *rqp;
{
  return (xdr_int(xdrs, &rqp->rq_bsize) &&
      xdr_bool(xdrs, &rqp->rq_active) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_bhardlimit) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_bsoftlimit) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_curblocks) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_fhardlimit) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_fsoftlimit) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_curfiles) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_btimeleft) &&
      xdr_u_long(xdrs, (unsigned long *)&rqp->rq_ftimeleft) );
}
#endif
#endif

/* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
 *
 *  The Perl interface
 *
 */

MODULE = Quota  PACKAGE = Quota
PROTOTYPES: DISABLE

void
query(dev,uid=getuid(),kind=0)
	char *	dev
	int	uid
	int     kind
	PPCODE:
	{
	  struct dqblk dqblk;
	  char *p = NULL;
	  int err;
#ifdef USE_IOCTL
	  struct quotactl qp;
	  int fd = -1;
#endif
#ifdef SGI_XFS
	  if(!strncmp(dev, "(XFS)", 5)) {
	    fs_disk_quota_t xfs_dqblk;
#ifndef linux
	    err = quotactl(Q_XGETQUOTA, dev+5, uid, CADR &xfs_dqblk);
#else
	    err = quotactl(QCMD(Q_XGETQUOTA, ((kind == 2) ? XQM_PRJQUOTA : ((kind == 1) ? XQM_GRPQUOTA : XQM_USRQUOTA))), dev+5, uid, CADR &xfs_dqblk);
#endif
	    if(!err) {
	      EXTEND(sp, 8);
	      PUSHs(sv_2mortal(newSViv(QX_DIV(xfs_dqblk.d_bcount))));
	      PUSHs(sv_2mortal(newSViv(QX_DIV(xfs_dqblk.d_blk_softlimit))));
	      PUSHs(sv_2mortal(newSViv(QX_DIV(xfs_dqblk.d_blk_hardlimit))));
	      PUSHs(sv_2mortal(newSViv(xfs_dqblk.d_btimer)));
	      PUSHs(sv_2mortal(newSViv(xfs_dqblk.d_icount)));
	      PUSHs(sv_2mortal(newSViv(xfs_dqblk.d_ino_softlimit)));
	      PUSHs(sv_2mortal(newSViv(xfs_dqblk.d_ino_hardlimit)));
	      PUSHs(sv_2mortal(newSViv(xfs_dqblk.d_itimer)));
	    }
	  }
	  else
#endif
#ifdef SOLARIS_VXFS
          if(!strncmp(dev, "(VXFS)", 6)) {
            struct vx_dqblk vxfs_dqb;
            err = vx_quotactl(VX_GETQUOTA, dev+6, uid, CADR &vxfs_dqb);
            if(!err) {
              EXTEND(sp,8);
              PUSHs(sv_2mortal(newSViv(Q_DIV(vxfs_dqb.dqb_curblocks))));
              PUSHs(sv_2mortal(newSViv(Q_DIV(vxfs_dqb.dqb_bsoftlimit))));
              PUSHs(sv_2mortal(newSViv(Q_DIV(vxfs_dqb.dqb_bhardlimit))));
              PUSHs(sv_2mortal(newSViv(vxfs_dqb.dqb_btimelimit)));
              PUSHs(sv_2mortal(newSViv(vxfs_dqb.dqb_curfiles)));
              PUSHs(sv_2mortal(newSViv(vxfs_dqb.dqb_fsoftlimit)));
              PUSHs(sv_2mortal(newSViv(vxfs_dqb.dqb_fhardlimit)));
              PUSHs(sv_2mortal(newSViv(vxfs_dqb.dqb_ftimelimit)));
            }
          }
          else
#endif
#ifdef AFSQUOTA
	  if(!strncmp(dev, "(AFS)", 5)) {
	    if (!afs_check()) {  /* check is *required* as setup! */
	      errno = EINVAL;
	    }
	    else {
	      int maxQuota, blocksUsed;

	      err = afs_getquota(dev + 5, &maxQuota, &blocksUsed);
	      if(!err) {
		EXTEND(sp, 8);
		PUSHs(sv_2mortal(newSViv(blocksUsed)));
		PUSHs(sv_2mortal(newSViv(maxQuota)));
		PUSHs(sv_2mortal(newSViv(maxQuota)));
		PUSHs(sv_2mortal(newSViv(0)));
		PUSHs(sv_2mortal(newSViv(0)));
		PUSHs(sv_2mortal(newSViv(0)));
		PUSHs(sv_2mortal(newSViv(0)));
		PUSHs(sv_2mortal(newSViv(0)));
	      }
	    }
	  }
	  else
#endif
	  {
	    if((*dev != '/') && (p = strchr(dev, ':'))) {
#ifndef NO_RPC
	      *p = '\0';
	      err = getnfsquota(dev, p+1, uid, &dqblk);
	      *p = ':';
#else /* NO_RPC */
	      errno = ENOSYS;
              err = -1;
#endif /* NO_RPC */
            }
	    else {
#ifdef USE_IOCTL
	      qp.op = Q_GETQUOTA;
	      qp.uid = uid;
	      qp.addr = (char *)&dqblk;
	      err = (((fd = open(dev, O_RDONLY)) == -1) ||
		     (ioctl(fd, Q_QUOTACTL, &qp) == -1));
#else /* not USE_IOCTL */
#ifdef Q_CTL_V3  /* Linux */
	      err = linuxquota_query(dev, uid, (kind != 0), &dqblk);
#else /* not Q_CTL_V3 */
#ifdef Q_CTL_V2
#ifdef AIX
              /* AIX quotactl doesn't fail if path does not exist!? */
              struct stat st;
#if defined(HAVE_JFS2)
              if (strncmp(dev, "(JFS2)", 6) == 0) {
                if (stat(dev + 6, &st)) {
		  err = 1;
                }
		else {
		  quota64_t user_quota;

		  err = quotactl(dev + 6, QCMD(Q_J2GETQUOTA, ((kind != 0) ? GRPQUOTA : USRQUOTA)),
                                 uid, CADR &user_quota);
		  dqblk.dqb_curblocks  = user_quota.bused;
		  dqblk.dqb_bsoftlimit = user_quota.bsoft;
		  dqblk.dqb_bhardlimit = user_quota.bhard;
		  dqblk.dqb_ihardlimit = user_quota.ihard;
		  dqblk.dqb_isoftlimit = user_quota.isoft;
		  dqblk.dqb_curinodes = user_quota.iused;
		  dqblk.dqb_btime = user_quota.btime;
		  dqblk.dqb_itime = user_quota.itime;
		}
              }
#endif /* HAVE_JFS2 */
              else if (stat(dev, &st)) {
                err = 1;
              }
              else
#endif /* AIX */
	      err = quotactl(dev, QCMD(Q_GETQUOTA, ((kind != 0) ? GRPQUOTA : USRQUOTA)), uid, CADR &dqblk);
#else /* not Q_CTL_V2 */
	      err = quotactl(Q_GETQUOTA, dev, uid, CADR &dqblk);
#endif /* not Q_CTL_V2 */
#endif /* Q_CTL_V3 */
#endif /* not USE_IOCTL */
	    }
	    if(!err) {
	      EXTEND(sp, 8);
	      PUSHs(sv_2mortal(newSViv(Q_DIV(dqblk.QS_BCUR))));
	      PUSHs(sv_2mortal(newSViv(Q_DIV(dqblk.QS_BSOFT))));
	      PUSHs(sv_2mortal(newSViv(Q_DIV(dqblk.QS_BHARD))));
	      PUSHs(sv_2mortal(newSViv(dqblk.QS_BTIME)));
	      PUSHs(sv_2mortal(newSViv(dqblk.QS_FCUR)));
	      PUSHs(sv_2mortal(newSViv(dqblk.QS_FSOFT)));
	      PUSHs(sv_2mortal(newSViv(dqblk.QS_FHARD)));
	      PUSHs(sv_2mortal(newSViv(dqblk.QS_FTIME)));
	    }
#ifdef USE_IOCTL
	    if(fd != -1) close(fd);
#endif
	  }
        }

int
setqlim(dev,uid,bs,bh,fs,fh,timelimflag=0,kind=0)
	char *	dev
	int	uid
	int	bs
	int	bh
	int	fs
	int	fh
	int	timelimflag
	int     kind
	CODE:
	{
	  struct dqblk dqblk;
#ifdef USE_IOCTL
	  struct quotactl qp;
	  int fd;

	  qp.op = Q_SETQLIM;
	  qp.uid = uid;
	  qp.addr = (char *)&dqblk;
#endif
	  if(timelimflag != 0) timelimflag = 1;
#ifdef SGI_XFS
	  if(!strncmp(dev, "(XFS)", 5)) {
	    fs_disk_quota_t xfs_dqblk;

	    xfs_dqblk.d_blk_softlimit = QX_MUL(bs);
	    xfs_dqblk.d_blk_hardlimit = QX_MUL(bh);
	    xfs_dqblk.d_btimer        = timelimflag;
	    xfs_dqblk.d_ino_softlimit = fs;
	    xfs_dqblk.d_ino_hardlimit = fh;
	    xfs_dqblk.d_itimer        = timelimflag;
	    xfs_dqblk.d_fieldmask     = FS_DQ_LIMIT_MASK;
	    xfs_dqblk.d_flags         = XFS_USER_QUOTA;
#ifndef linux
	    RETVAL = quotactl(Q_XSETQLIM, dev+5, uid, CADR &xfs_dqblk);
#else
	    RETVAL = quotactl(QCMD(Q_XSETQLIM, ((kind == 2) ? XQM_PRJQUOTA : ((kind == 1) ? XQM_GRPQUOTA : XQM_USRQUOTA))), dev+5, uid, CADR &xfs_dqblk);
#endif
	  }
	  else
	    /* if not xfs, than it's a classic IRIX efs file system */
#endif
#ifdef SOLARIS_VXFS
          if(!strncmp(dev, "(VXFS)", 6)) {
            struct vx_dqblk vxfs_dqb;

            vxfs_dqb.dqb_bsoftlimit = Q_MUL(bs);
            vxfs_dqb.dqb_bhardlimit = Q_MUL(bh);
            vxfs_dqb.dqb_btimelimit = timelimflag;
            vxfs_dqb.dqb_fsoftlimit = fs;
            vxfs_dqb.dqb_fhardlimit = fh;
            vxfs_dqb.dqb_ftimelimit = timelimflag;
            RETVAL = vx_quotactl(VX_SETQUOTA, dev+6, uid, CADR &vxfs_dqb);
        }
        else
#endif
#ifdef AFSQUOTA
	  if(!strncmp(dev, "(AFS)", 5)) {
	    if (!afs_check()) {  /* check is *required* as setup! */
	      errno = EINVAL;
	      RETVAL = -1;
	    }
	    else
	      RETVAL = afs_setqlim(dev + 5, bh);
	  }
	  else
#endif
#if defined(HAVE_JFS2)
          if(strncmp(dev, "(JFS2)", 6) == 0) {
            quota64_t user_quota;

            RETVAL = quotactl(dev + 6, QCMD(Q_J2GETQUOTA, ((kind != 0) ? GRPQUOTA : USRQUOTA)),
                              uid, CADR &user_quota);
            if (RETVAL == 0) {
              user_quota.bsoft = bs;
              user_quota.bhard = bh;
              user_quota.btime = timelimflag;
              user_quota.isoft = fs;
              user_quota.ihard = fh;
              user_quota.itime = timelimflag;
              RETVAL = quotactl(dev + 6, QCMD(Q_J2PUTQUOTA, ((kind != 0) ? GRPQUOTA : USRQUOTA)),
                                uid, CADR &user_quota);
            }
          }
          else
#endif /* HAVE_JFS2 */
	  {
	    dqblk.QS_BSOFT = Q_MUL(bs);
	    dqblk.QS_BHARD = Q_MUL(bh);
	    dqblk.QS_BTIME = timelimflag;
	    dqblk.QS_FSOFT = fs;
	    dqblk.QS_FHARD = fh;
	    dqblk.QS_FTIME = timelimflag;
#ifdef USE_IOCTL
	    if((fd = open(dev, O_RDONLY)) != -1) {
	      RETVAL = (ioctl(fd, Q_QUOTACTL, &qp) != 0);
	      close(fd);
	    }
	    else
	      RETVAL = -1;
#else
#ifdef Q_CTL_V3  /* Linux */
	    RETVAL = linuxquota_setqlim (dev, uid, (kind != 0), &dqblk);
#else
#ifdef Q_CTL_V2
	    RETVAL = quotactl (dev, QCMD(Q_SETQUOTA,((kind != 0) ? GRPQUOTA : USRQUOTA)), uid, CADR &dqblk);
#else
	    RETVAL = quotactl (Q_SETQLIM, dev, uid, CADR &dqblk);
#endif
#endif
#endif
	  }
	}
	OUTPUT:
	RETVAL

int
sync(dev=NULL)
	char *	dev
	CODE:
#ifdef SOLARIS_VXFS
        if ((dev != NULL) && !strncmp(dev, "(VXFS)", 6)) {
          RETVAL = vx_quotactl(VX_QSYNCALL, dev+6, 0, NULL);
        }
        else
#endif
#ifdef AFSQUOTA
	if ((dev != NULL) && !strncmp(dev, "(AFS)", 5)) {
	  if (!afs_check()) {
	    errno = EINVAL;
	    RETVAL = -1;
	  }
	  else {
	    int foo1, foo2;
	    RETVAL = (afs_getquota(dev + 5, &foo1, &foo2) ? -1 : 0);
	  }
	}
	else
#endif
#ifdef USE_IOCTL
	{
	  struct quotactl qp;
	  int fd;

	  if(dev == NULL) {
	    qp.op = Q_ALLSYNC;
	    dev = "/";   /* is probably ignored anyways */
	  }
	  else
	    qp.op = Q_SYNC;
	  if((fd = open(dev, O_RDONLY)) != -1) {
	    RETVAL = (ioctl(fd, Q_QUOTACTL, &qp) != 0);
	    if(errno == ESRCH) errno = EINVAL;
	    close(fd);
	  }
	  else
	    RETVAL = -1;
	}
#else
        {
#ifdef Q_CTL_V3  /* Linux */
#ifdef SGI_XFS
          if ((dev != NULL) && (!strncmp(dev, "(XFS)", 5))) {
            struct fs_quota_stat fsq_stat;

            if (!quotactl(QCMD(Q_XGETQSTAT, USRQUOTA), dev+5, 0, CADR &fsq_stat)) {
              if (fsq_stat.qs_flags & (XFS_QUOTA_UDQ_ACCT | XFS_QUOTA_GDQ_ACCT))
                RETVAL = 0;
              else if ( (strcmp(dev+5, "/") == 0) &&
                        (((fsq_stat.qs_flags & 0xff00) >> 8) & (XFS_QUOTA_UDQ_ACCT | XFS_QUOTA_GDQ_ACCT)) )
                RETVAL = 0;
              else {
                errno = ENOENT;
                RETVAL = -1;
              }
            }
            else {
              errno = ENOENT;
              RETVAL = -1;
            }
          }
          else
#endif
	  RETVAL = linuxquota_sync (dev, FALSE);
#else
#ifdef Q_CTL_V2
#ifdef AIX
          struct stat st;
#endif
	  if(dev == NULL) dev = "/";
#ifdef AIX
#if defined(HAVE_JFS2)
          if (strncmp(dev, "(JFS2)", 6) == 0) dev += 6;
#endif
	  if (stat(dev, &st)) RETVAL = -1;
	  else
#endif
	  RETVAL = quotactl(dev, QCMD(Q_SYNC, USRQUOTA), 0, NULL);
#else
#ifdef SGI_XFS
#define XFS_UQUOTA (XFS_QUOTA_UDQ_ACCT|XFS_QUOTA_UDQ_ENFD)
	  /* Q_SYNC is not supported on XFS filesystems, so emulate it */
	  if ((dev != NULL) && (!strncmp(dev, "(XFS)", 5))) {
	    fs_quota_stat_t fsq_stat;

	    sync();

	    RETVAL = quotactl(Q_GETQSTAT, dev+5, 0, CADR &fsq_stat);

	    if (!RETVAL && ((fsq_stat.qs_flags & XFS_UQUOTA) != XFS_UQUOTA)) {
	      errno = ENOENT;
	      RETVAL = -1;
	    }
	  }
	  else
#endif
	  RETVAL = quotactl(Q_SYNC, dev, 0, NULL);
#endif
#endif
        }
#endif
	OUTPUT:
	RETVAL

void
rpcquery(host,path,uid=getuid())
	char *	host
	char *	path
	int	uid
	PPCODE:
	{
#ifndef NO_RPC
	  struct dqblk dqblk;
	  if(getnfsquota(host, path, uid, &dqblk) == 0) {
	    EXTEND(sp, 8);
	    PUSHs(sv_2mortal(newSViv(Q_DIV(dqblk.QS_BCUR))));
	    PUSHs(sv_2mortal(newSViv(Q_DIV(dqblk.QS_BSOFT))));
	    PUSHs(sv_2mortal(newSViv(Q_DIV(dqblk.QS_BHARD))));
	    PUSHs(sv_2mortal(newSViv(dqblk.QS_BTIME)));

	    PUSHs(sv_2mortal(newSViv((int) dqblk.QS_FCUR)));
	    PUSHs(sv_2mortal(newSViv((int) dqblk.QS_FSOFT)));
	    PUSHs(sv_2mortal(newSViv((int) dqblk.QS_FHARD)));
	    PUSHs(sv_2mortal(newSViv((int) dqblk.QS_FTIME)));
	  }
#else
	  errno = ENOSYS;
#endif
	}

void
rpcpeer(port=0,use_tcp=FALSE,timeout=RPC_DEFAULT_TIMEOUT)
	unsigned port
	unsigned use_tcp 
	unsigned timeout 
	PPCODE:
	{
#ifndef NO_RPC
	  quota_rpc_cfg.port = port;
	  quota_rpc_cfg.use_tcp = use_tcp;
	  quota_rpc_cfg.timeout = timeout;
#endif
	}

int
rpcauth(uid=-1,gid=-1,hostname=NULL)
	int uid
	int gid
	char * hostname
	CODE:
	{
#ifndef NO_RPC
          if ((uid == -1) && (gid == -1) && (hostname==NULL)) {
            /* reset to default values */
            quota_rpc_auth.uid = uid;
            quota_rpc_auth.gid = gid;
            quota_rpc_auth.hostname[0] = 0;
            RETVAL = 0;

          } else {
            if (uid == -1)
              quota_rpc_auth.uid = getuid();
            else
              quota_rpc_auth.uid = uid;

            if (gid == -1)
              quota_rpc_auth.gid = getgid();
            else
              quota_rpc_auth.gid = gid;

            if (hostname == NULL) {
              RETVAL = gethostname(quota_rpc_auth.hostname, MAX_MACHINE_NAME);
            } else if (strlen(hostname) < MAX_MACHINE_NAME) {
              strcpy(quota_rpc_auth.hostname, hostname);
              RETVAL = 0;
            } else {
              errno = EINVAL;
              RETVAL = -1;
            }
          }
#endif
	}
	OUTPUT:
	RETVAL

int
setmntent()
	CODE:
	{
#ifndef AIX
#ifndef NO_MNTENT
#ifndef NO_OPEN_MNTTAB
	  if(mtab != NULL) endmntent(mtab);
	  if((mtab = setmntent(MOUNTED, "r")) == NULL)
#else
	  if(mtab != NULL) fclose(mtab);
	  if((mtab = std_fopen (MOUNTED,"r")) == NULL)
#endif
	    RETVAL = -1;
	  else
	    RETVAL = 0;
#else
	  /* if(mtab != NULL) free(mtab); */
	  if((mtab_size = getmntinfo(&mtab, MNT_NOWAIT)) <= 0)
	    RETVAL = -1;
	  else
	    RETVAL = 0;
	  mntp = mtab;
#endif
#else /* AIX */
	  int count, space;

          if(mtab != NULL) free(mtab);
	  count = mntctl(MCTL_QUERY, sizeof(space), (char *) &space);
	  if (count == 0) {
	    mtab = (struct vmount *) malloc(space);
	    if (mtab != NULL) {
	      count = mntctl(MCTL_QUERY, space, (char *) mtab);
	      if (count > 0) {
	        aix_mtab_count = count;
	        aix_mtab_idx   = 0;
		RETVAL = 0;
	      }
	      else {  /* error, or size changed between calls */
		if (count == 0) errno = EINTR;
	        RETVAL = -1;
	      }
	    }
	    else
	      RETVAL = -1;
	  }
	  else if (count < 0)
	    RETVAL = -1;
	  else { /* should never happen */
	    errno = ENOENT;
	    RETVAL = -1;
	  }
#endif
	}
	OUTPUT:
	RETVAL

void
getmntent()
	PPCODE:
	{
#ifndef AIX
#ifndef NO_MNTENT
#ifndef NO_OPEN_MNTTAB
	  struct mntent *mntp;
	  if(mtab != NULL) {
	    mntp = getmntent(mtab);
	    if(mntp != NULL) {
	      EXTEND(sp, 4);
	      PUSHs(sv_2mortal(newSVpv(mntp->mnt_fsname, strlen(mntp->mnt_fsname))));
	      PUSHs(sv_2mortal(newSVpv(mntp->mnt_dir, strlen(mntp->mnt_dir))));
	      PUSHs(sv_2mortal(newSVpv(mntp->mnt_type, strlen(mntp->mnt_type))));
	      PUSHs(sv_2mortal(newSVpv(mntp->mnt_opts, strlen(mntp->mnt_opts))));
	    }
	  }
	  else
	    errno = EBADF;
#else
	  struct mnttab mntp;
	  if(mtab != NULL) {
	    if(getmntent(mtab, &mntp) == 0)  {
	      EXTEND(sp, 4);
	      PUSHs(sv_2mortal(newSVpv(mntp.mnt_special, strlen(mntp.mnt_special))));
	      PUSHs(sv_2mortal(newSVpv(mntp.mnt_mountp, strlen(mntp.mnt_mountp))));
	      PUSHs(sv_2mortal(newSVpv(mntp.mnt_fstype, strlen(mntp.mnt_fstype))));
	      PUSHs(sv_2mortal(newSVpv(mntp.mnt_mntopts, strlen(mntp.mnt_mntopts))));
	    }
	  }
	  else
	    errno = EBADF;
#endif
#else
#ifdef OSF_QUOTA
          char *fstype = getvfsbynumber((int)mntp->f_type);
#endif
	  if((mtab != NULL) && mtab_size) {
	    EXTEND(sp,4);
	    PUSHs(sv_2mortal(newSVpv(mntp->f_mntfromname, strlen(mntp->f_mntfromname))));
	    PUSHs(sv_2mortal(newSVpv(mntp->f_mntonname, strlen(mntp->f_mntonname))));
#ifdef OSF_QUOTA
            if (fstype != (char *) -1)
              PUSHs(sv_2mortal(newSVpv(fstype, strlen(fstype))));
            else
#endif
#ifndef __OpenBSD__
              PUSHs(sv_2mortal(newSViv((IV)mntp->f_type)));
#else
              /* OpenBSD struct statfs lacks the f_type member (starting with release 2.7) */
              PUSHs(sv_2mortal(newSViv((IV)"")));
#endif
	    PUSHs(sv_2mortal(newSViv((IV)mntp->f_flags)));
	    mtab_size--;
	    mntp++;
	  }
#endif
#else /* AIX */
	  struct vmount *vmp;
	  char *cp;
	  int i;

          if ((mtab != NULL) && (aix_mtab_idx < aix_mtab_count)) {
	    cp = (char *) mtab;
	    for (i=0; i<aix_mtab_idx; i++) {
	      vmp = (struct vmount *) cp;
	      cp += vmp->vmt_length;
	    }
	    vmp = (struct vmount *) cp;
	    aix_mtab_idx += 1;

	    EXTEND(sp,4);
	    if ((vmp->vmt_gfstype != MNT_NFS) && (vmp->vmt_gfstype != MNT_NFS3)) {
	      cp = vmt2dataptr(vmp, VMT_OBJECT);
	      PUSHs(sv_2mortal(newSVpv(cp, strlen(cp))));
	    }
	    else {
	      uchar *mp, *cp2;
	      cp = vmt2dataptr(vmp, VMT_HOST);
	      cp2 = vmt2dataptr(vmp, VMT_OBJECT);
	      mp = malloc(strlen(cp) + strlen(cp2) + 2);
	      if (mp != NULL) {
		strcpy(mp, cp);
		strcat(mp, ":");
		strcat(mp, cp2);
	        PUSHs(sv_2mortal(newSVpv(mp, strlen(mp))));
		free(mp);
	      }
	      else {
	        cp = "?";
	        PUSHs(sv_2mortal(newSVpv(cp, strlen(cp))));
	      }
	    }
	    cp = vmt2dataptr(vmp, VMT_STUB);
	    PUSHs(sv_2mortal(newSVpv(cp, strlen(cp))));

	    switch(vmp->vmt_gfstype) {
	      case MNT_NFS:   cp = "nfs"; break;
	      case MNT_NFS3:  cp = "nfs"; break;
	      case MNT_JFS:   cp = "jfs"; break;
#if defined(MNT_AIX) && defined(MNT_J2) && (MNT_AIX==MNT_J2)
	      case MNT_J2:    cp = "jfs2"; break;
#else
#if defined(MNT_J2)
	      case MNT_J2:    cp = "jfs2"; break;
#endif
	      case MNT_AIX:   cp = "aix"; break;
#endif
	      case 4:         cp = "afs"; break;
	      case MNT_CDROM: cp = "cdrom,ignore"; break;
	      default:        cp = "unknown,ignore"; break;
	    }
	    PUSHs(sv_2mortal(newSVpv(cp, strlen(cp))));

	    cp = vmt2dataptr(vmp, VMT_ARGS);
	    PUSHs(sv_2mortal(newSVpv(cp, strlen(cp))));
	  }
#endif
	}

void
endmntent()
	PPCODE:
	{
	  if(mtab != NULL) {
#ifndef AIX
#ifndef NO_MNTENT
#ifndef NO_OPEN_MNTTAB
	    endmntent(mtab);   /* returns always 1 in SunOS */
#else
	    std_fclose (mtab);
#endif
	    /* #else: if(mtab != NULL) free(mtab); */
#endif
#else /* AIX */
            free(mtab);
#endif
	    mtab = NULL;
	  }
	}

char *
getqcargtype()
	CODE:
	static char ret[25];
#if defined(USE_IOCTL) || defined(QCARG_MNTPT)
	strcpy(ret, "mntpt");
#else
#if defined(HAVE_JFS2)
	strcpy(ret, "any,JFS2");
#else
#if defined(AIX) || defined(OSF_QUOTA)
	strcpy(ret, "any");
#else
#ifdef Q_CTL_V2
	strcpy(ret, "qfile");
#else
/* this branch applies to Q_CTL_V3 (Linux) too */
#ifdef SGI_XFS
	strcpy(ret, "dev,XFS");
#else
	strcpy(ret, "dev");
#endif
#endif
#endif
#endif
#endif
#ifdef AFSQUOTA
        strcat(ret, ",AFS");
#endif
#ifdef SOLARIS_VXFS
        strcat(ret, ",VXFS");
#endif
        RETVAL = ret;
	OUTPUT:
	RETVAL

