#!/bin/sh
#
# Used to build the overlay file needed to add the files from the
# Razor-Microkernel project to a Microkernel ISO image.  The file
# built by this script (along with any other gzipped tarfiles in
# the build_files subdirectory) should be placed into the "dependencies"
# subdirectory of the directory being used to build the Microkernel
# (where it will be picked up from by the build script).

# define a function we can use to print out the usage for this script
usage()
{
cat << EOF

Usage: $0 OPTIONS

This script builds a gzipped tarfile containing all of the files necessary to
build an instance of the Razor Microkernel ISO.

OPTIONS:
   -h, --help                 print usage for this command
   -r, --reuse-prev-dl        reuse the downloads rather than downloading again
   -b, --builtin-list FILE    file containing extensions to install as builtin
   -m, --mirror-list FILE     file containing extensions to add to TCE mirror
   -p, --build-prod-image     build a production ISO (no openssh, no passwd)
   -d, --build-dev-image      build a development ISO (include openssh, passwd)

Note; currently, the default is to build a development ISO (which includes the
openssh.tcz extension along with the openssh/openssl configuration file changes
and the passwd changes needed to access the Microkernel image from the command
line or via the console)

EOF
}

# initialize a few variables to hold the options passed in by the user
BUILTIN_LIST=
MIRROR_LIST=
RE_USE_PREV_DL='no'
BUILD_DEV_ISO='yes'

# options may be followed by one colon to indicate they have a required argument
if ! options=$(getopt -o hrb:m:pd -l help,reuse-prev-dl,builtin-list:,mirror-list:,build-prod-image,build-dev-image -- "$@")
then
    usage
    # something went wrong, getopt will put out an error message for us
    exit 1
fi
set -- $options

while [ $# -gt 0 ]
do
  case $1 in
  -r|--reuse-prev-dl) RE_USE_PREV_DL='yes';;
  -b|--builtin-list) BUILTIN_LIST=`echo $2 | tr -d "'"`; shift;;
  -m|--mirror-list) MIRROR_LIST=`echo $2 | tr -d "'"`; shift;;
  -p|--build-prod-image) BUILD_DEV_ISO='no';;
  -d|--build-dev-image) BUILD_DEV_ISO='yes';;
  -h|--help) usage; exit 0;;
  (--) shift; break;;
  (-*) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
  esac
  shift
done

if [  -z $BUILTIN_LIST ] || [ -z $MIRROR_LIST ]; then
  echo "\nError (Missing Argument); the 'builtin-list' and 'mirror-list' must both be specified"
  usage
  exit 1
elif [ ! -r $BUILTIN_LIST ] || [ ! -r $MIRROR_LIST ]; then
  echo "\nError; the 'builtin-list' and 'mirror-list' values must both be readable files"
  usage
  exit 1
fi

# if not, then make sure we're starting with a clean (i.e. empty) build directory
if [ $RE_USE_PREV_DL = 'no' ]
then
  if [ ! -d tmp-build-dir ]; then
    # make a directory we can use to build our gzipped tarfile
    mkdir tmp-build-dir
  else
    # directory exists, so remove the contents
    rm -rf tmp-build-dir/*
  fi
fi

# initialize a couple of variables that we'll use later

TOP_DIR=`pwd`
TCL_MIRROR_URI='http://distro.ibiblio.org/tinycorelinux/4.x/x86/tcz'
TCL_ISO_URL='http://distro.ibiblio.org/tinycorelinux/4.x/x86/release/Core-current.iso'
RUBY_GEMS_URL='http://production.cf.rubygems.org/rubygems/rubygems-1.8.24.tgz'
#MCOLLECTIVE_URL='http://puppetlabs.com/downloads/mcollective/mcollective-1.2.1.tgz'
MCOLLECTIVE_URL='http://puppetlabs.com/downloads/mcollective/mcollective-2.0.0.tgz'

# create a folder to hold the gzipped tarfile that will contain all of
# dependencies

mkdir -p tmp-build-dir/build_dir/dependencies

# copy over the scripts that are needed to actually build the ISO into
# the build_dir (from there, they will be included into a single
# gzipped tarfile that can be unpacked and will contain almost all of
# the files/tools needed to build the Microkernel ISO)

cp -p iso-build-files/* tmp-build-dir/build_dir
if [ $BUILD_DEV_ISO = 'no' ]
then
  sed -i 's/ISO_NAME=rz_mk_dev-image/ISO_NAME=rz_mk_prod-image/' tmp-build-dir/build_dir/rebuild_iso.sh
fi

# create a copy of the modifications to the DHCP client configuration that
# are needed for the Razor Microkernel Controller to find the appropriate
# Razor server for it's first checkin

mkdir -p tmp-build-dir/etc/init.d
cp -p etc/init.d/dhcp.sh tmp-build-dir/etc/init.d
mkdir -p tmp-build-dir/usr/share/udhcpc
cp -p usr/share/udhcpc/dhcp_mk_config.script tmp-build-dir/usr/share/udhcpc

# create copies of the files from this project that will be placed
# into the /usr/local/bin directory in the Razor Microkernel ISO

mkdir -p tmp-build-dir/usr/local/bin
cp -p rz_mk_*.rb tmp-build-dir/usr/local/bin

# create copies of the files from this project that will be placed
# into the /usr/local/lib/ruby/1.8/razor_microkernel directory in the Razor
# Microkernel ISO

mkdir -p tmp-build-dir/usr/local/lib/ruby/1.8/razor_microkernel
cp -p razor_microkernel/*.rb tmp-build-dir/usr/local/lib/ruby/1.8/razor_microkernel

# create copies of the MCollective agents from this project (will be placed
# into the /usr/local/tce.installed/$mcoll_dir/plugins/mcollective/agent
# directory in the Razor Microkernel ISO

file=`echo $MCOLLECTIVE_URL | awk -F/ '{print $NF}'`
mcoll_dir=`echo $file | cut -d'.' -f-3`
mkdir -p tmp-build-dir/usr/local/tce.installed/$mcoll_dir/plugins/mcollective/agent
cp -p configuration-agent/configuration.rb facter-agent/facteragent.rb \
    tmp-build-dir/usr/local/tce.installed/$mcoll_dir/plugins/mcollective/agent

# create a copy of the files from this project that will be placed into the
# /opt directory in the Razor Microkernel ISO; as part of this process will
# download the latest version of the gems in the 'gem.list' file into the
# appropriate directory to use in the build process (rather than including
# fixed versions of those gems as part of the Razor-Microkernel project)

mkdir -p tmp-build-dir/opt/gems
cp -p opt/bootsync.sh tmp-build-dir/opt
cp -p opt/gems/gem.list tmp-build-dir/opt/gems
cd tmp-build-dir/opt/gems
for file in `cat gem.list`; do
  if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f $file*.gem ]
  then
    gem fetch $file
  fi
done
cd $TOP_DIR

# create a copy of the local TCL Extension mirror that we will be running within
# our Microkernel instances

mkdir -p tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz
cp -p tmp/tinycorelinux/*.yaml tmp-build-dir/tmp/tinycorelinux
for file in `cat $MIRROR_LIST`; do
  if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz/$file ]
  then
    wget -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz $TCL_MIRROR_URI/$file
    wget -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz -q $TCL_MIRROR_URI/$file.md5.txt
    wget -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz -q $TCL_MIRROR_URI/$file.info
    wget -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz -q $TCL_MIRROR_URI/$file.list
    wget -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz -q $TCL_MIRROR_URI/$file.dep
  fi
done

# download a set of extensions that will be installed during the Microkernel
# boot process.  These files will be placed into the /tmp/builtin directory in
# the Microkernel ISO.  The list of files downloaded (and loaded at boot) are
# assumed to be contained in the file specified by the BUILTIN_LIST parameter

echo `pwd`
mkdir -p tmp-build-dir/tmp/builtin/optional
rm tmp-build-dir/tmp/builtin/onboot.lst 2> /dev/null
for file in `cat $BUILTIN_LIST`; do
  if [ $BUILD_DEV_ISO = 'yes' ] || [ ! $file = 'openssh.tcz' ]; then
    if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f tmp-build-dir/tmp/builtin/optional/$file ]
    then
      wget -P tmp-build-dir/tmp/builtin/optional $TCL_MIRROR_URI/$file
      wget -P tmp-build-dir/tmp/builtin/optional -q $TCL_MIRROR_URI/$file.md5.txt
      wget -P tmp-build-dir/tmp/builtin/optional -q $TCL_MIRROR_URI/$file.dep
    fi
    echo $file >> tmp-build-dir/tmp/builtin/onboot.lst
  elif [ $BUILD_DEV_ISO = 'no' ] && [ -f tmp-build-dir/tmp/builtin/optional/$file ]
  then
    rm tmp-build-dir/tmp/builtin/optional/$file
    rm tmp-build-dir/tmp/builtin/optional/$file.md5.txt 2> /dev/null
    rm tmp-build-dir/tmp/builtin/optional/$file.dep 2> /dev/null
  fi
done

# download the ruby-gems distribution (will be installed during the boot
# process prior to starting the Microkernel initialization process)

file=`echo $RUBY_GEMS_URL | awk -F/ '{print $NF}'`
if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f tmp-build-dir/opt/$file ]
then
  wget -P tmp-build-dir/opt $RUBY_GEMS_URL
fi

# copy over a couple of initial configuration files that will be included in the
# /tmp and /etc directories of the Microkernel instance (the first two control the
# initial behavior of the Razor Microkernel Controller, the third disables automatic
# login of the tc user when the Microkernel finishes booting)

cp -p tmp/first_checkin.yaml tmp/mk_conf.yaml tmp-build-dir/tmp
cp -p etc/inittab tmp-build-dir/etc

# get a copy of the current Tiny Core Linux "Core" ISO

file=`echo $TCL_ISO_URL | awk -F/ '{print $NF}'`
if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f tmp-build-dir/build_dir/$file ]
then
  wget -P tmp-build-dir/build_dir $TCL_ISO_URL
fi

# download the MCollective, unpack it in the appropriate location, and
# add a couple of soft links

file=`echo $MCOLLECTIVE_URL | awk -F/ '{print $NF}'`
mcoll_dir=`echo $file | cut -d'.' -f-3`
if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f tmp-build-dir/$file ]
then
  wget -P tmp-build-dir $MCOLLECTIVE_URL
fi
cd tmp-build-dir/usr/local/tce.installed
tar zxvf $TOP_DIR/tmp-build-dir/$file
cd $TOP_DIR/tmp-build-dir
rm usr/local/mcollective usr/local/bin/mcollectived 2> /dev/null
ln -s /usr/local/tce.installed/$mcoll_dir usr/local/mcollective
ln -s /usr/local/mcollective/bin/mcollectived usr/local/bin/mcollectived
cd $TOP_DIR

# add a soft-link in what will become the /usr/local/sbin directory in the
# Microkernel ISO (this fixes an issue with where Facter expects to find
# the 'dmidecode' executable)

mkdir -p tmp-build-dir/usr/sbin
rm tmp-build-dir/usr/sbin 2> /dev/null
ln -s /usr/local/sbin/dmidecode tmp-build-dir/usr/sbin 2> /dev/null

# copy over a few additional dependencies (currently, this includes the
# following files:
#   1. ssh-setup-files.tar.gz -> contains the setup files needed for the
#         SSH/SSL along with the passwd and shadow files (used for development
#         access to the Microkernel); if the '--build-prod-image' flag is set,
#         then this file will be skipped
#   2. mcollective-setup-files.tar.gz -> contains the setup files needed for
#         running the mcollective daemon
#   3. mk-open-vm-tools.tar.gz -> contains the files needed for the
#         'open_vm_tools.tcz' extension

cp -p additional-build-files/*.gz tmp-build-dir/build_dir/dependencies
# if we're building a production system, remove the SSH setup files from the
# files we just copied over to the dependencies directory
if [ $BUILD_DEV_ISO = 'no' ]; then
  rm tmp-build-dir/build_dir/dependencies/ssh-setup-files.tar.gz
fi

# get the latest util-linux.tcz, then extract the two executables that
# we need from that file (using the unsquashfs command)

file='util-linux.tcz'
if [ $RE_USE_PREV_DL = 'no' ] || [ ! -f tmp-build-dir/$file ]
then
  wget -P tmp-build-dir $TCL_MIRROR_URI/$file
fi
unsquashfs -f -d tmp-build-dir tmp-build-dir/util-linux.tcz `cat additional-build-files/util-linux-exec.lst`

# create a gzipped tarfile containing all of the files from the Razor-Microkernel
# project that we just copied over, along with the files that were downloaded from
# the network for the gems and TCL extensions; place this gzipped tarfile into
# a dependencies subdirectory of the build_dir

cd tmp-build-dir
tar zcvf build_dir/dependencies/razor-microkernel-files.tar.gz usr etc opt tmp

# and create a gzipped tarfile containing the dependencies folder and the set
# of scripts that are used to build the ISO (so that all the user has to do is
# copy over this one file to a directory somewhere and unpack it and they will
# be ready to build the ISO

cd build_dir
tar zcvf $TOP_DIR/build-files/razor-microkernel-overlay.tar.gz *
cd $TOP_DIR