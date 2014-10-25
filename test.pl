#!../../../perl

use blib;
use Quota;

while(1) {
  print "\nEnter path to get quota for (NFS possible; default '.'): ";
  chomp($path = <STDIN>);
  $path = "." unless $path =~ /\S/;

  while(1) {
    $dev = Quota::getqcarg($path);
    if(!$dev) {
      warn "$path: mount point not found\n";
      if(-d $path && $path !~ m#/.$#) {
	#
	# try to append "/." to get past automounter fs
	#
	$path .= "/.";
	warn "Trying $path instead...\n";
	redo;
      }
    }
    last;
  }
  redo if !$dev;
  print "Using device/argument \"$dev\"\n";

##
##  Check if quotas are present on this filesystem
##

  if($dev =~ m#^[^/]+:#) {
    print "Is a remote file system\n";
    last;
  }
  elsif(Quota::sync($dev) && ($! != 1)) {  # ignore EPERM
    warn "Quota::sync: ".Quota::strerr."\n";
    warn "Choose another file system - quotas not functional on this one\n";
  }
  else {
    print "Quotas are present on this filesystem (sync ok)\n";
    last;
  }
}

##
##  call with one argument (uid defaults to getuid()
##

print "\nQuery this fs with default uid (which is real uid) $>\n";
($bc,$bs,$bh,$bt,$fc,$fs,$fh,$ft) = Quota::query($dev);
if(defined($bc)) {
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($bt);
  $bt = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $bt;
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ft);
  $ft = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $ft;

  print "Your usage and limits are $bc ($bs/$bh/$bt) $fc ($fs/$fh/$ft)\n\n";
}
else {
  warn "Quota::query($dev): ",Quota::strerr,"\n\n";
}

##
##  call with two arguments
##

{
  print "Enter a uid to get quota for: ";
  chomp($uid = <STDIN>);
  unless($uid =~ /^\d{1,5}$/) {
    print "You have to enter a numerical uid in range 0..65535 here.\n";
    redo;
  }
}

($bc,$bs,$bh,$bt,$fc,$fs,$fh,$ft) = Quota::query($dev, $uid);
if(defined($bc)) {
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($bt);
  $bt = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $bt;
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ft);
  $ft = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $ft;

  print "Usage and limits for $uid are $bc ($bs/$bh/$bt) $fc ($fs/$fh/$ft)\n\n";
}
else {
  warn "Quota::query($dev,$uid): ",Quota::strerr,"\n\n";
}

##
##  get quotas via RPC
##

if($dev =~ m#^/#) {
  print "Query localhost via RPC.\n";

  ($bc,$bs,$bh,$bt,$fc,$fs,$fh,$ft) = Quota::rpcquery('localhost', $path);
  if(defined($bc)) {
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($bt);
    $bt = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $bt;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ft);
    $ft = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $ft;

    print "Your Usage and limits are $bc ($bs/$bh/$bt) $fc ($fs/$fh/$ft)\n\n";
  }
  else {
    warn Quota::strerr,"\n\n";
  }
  print "Query localhost via RPC for $uid.\n";

  ($bc,$bs,$bh,$bt,$fc,$fs,$fh,$ft) = Quota::rpcquery('localhost', $path, $uid);
  if(defined($bc)) {
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($bt);
    $bt = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $bt;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ft);
    $ft = sprintf("%d:%d %d/%d/%d", $hour,$min,$mon,$mday,$year) if $ft;

    print "Usage and limits for $uid are $bc ($bs/$bh/$bt) $fc ($fs/$fh/$ft)\n\n";
  }
  else {
    warn Quota::strerr,"\n\n";
  }

}
else {
  print "Skipping RPC query test - already done above.\n\n";
}

##
##  set quota block & file limits for user
##

print "Enter path to set quota (empty to skip): ";
chomp($path = <STDIN>);

if($path =~ /\S/) {
  print "New quota limits bs,bh,fs,fh for $uid (empty to abort): ";
  chomp($in = <STDIN>);
  if($in =~ /\S/) {
    $dev = Quota::getqcarg($path) || die "$path: $!\n";
    unless(Quota::setqlim($dev, $uid, split(/\s*,\s*/, $in), 1)) {
      print "Quota set for $uid\n";
    }
    else {
      warn Quota::strerr,"\n";
    }
  }
}

##
##  Force immediate update on disk
##

if($dev !~ m#^[^/]+:#) {
  Quota::sync($dev) && ($! != 1) && die "Quota::sync: ".Quota::strerr."\n";
}

