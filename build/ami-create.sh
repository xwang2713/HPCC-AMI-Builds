#!/bin/bash 
#---------------------------------------------------------------------------
# HPCC AMI creation script to install HPCC platform on Ubuntu 10.04LTS Amazon
# EC2 images located at http://cloud-images.ubuntu.com/releases/10.04/release/
# EC2 environment.  This script is to be passed into the User Data field
# and is run when the EC2 instance boots.
# Author:        Franz Nisswandt, HPCC Systems
#                franz.nisswandt@lexisnexis.com
# Date:          02/14/2012 - 05/02/2014
# Arguments:     None
# Source Code Modifications:
# 02/14/2012  Original version
# 02/16/2012  Modified for 11.10 Oneiric
# 02/28/2012  Modified to automatically gather kernel-ids for various regions
# 03/06/2012  Modified to use Charles's sub-account Amazon creds and use 
#             S3 buckets under that parent account.
# 05/02/2014  Handoff to Stuart Ort group
#
#             Modified to create ONE AMI in the home region where this image is running
#             It is expectedd that once the new AMI is tested, the other 7 region AMIs will
#             be bundled/migrated/uploaded/registered. The code block that does this 
#             for the rest of the regions is at the END of this script.
#
#---------------------------------------------------------------------------
## = = R E A D  M E  = = R E A D  M E  = = R E A D  M E  = =
## 
## There is a minimum required environment in order to run this script.
## The EC2 instance for building is ideally an EBS boot with about 20GB free.
## Alternatively, one can start up an instance storage EC2 instance with 
## lots of /mnt space, install your tools (below), run the script, and terminate.
## the bundles get saved to your S3 storage, so once created you don't really
## need them on your instance.
##
## 1. There must be - at least - 10GB free in /mnt. 
## 2. apt-get universe, ec2-api-tools and ec2-ami-tools need to be installed
## 3. mnt needs enough storage to create a 10GB image (though it is sparse so might
## not necessarily require the full amount)
##
## private keys (pk-*.pem and cert-*.pem) go in ~/.ec2 (one pair of keys only!) 
## also: if you want to use the s3 copy commands, you'll need to put your access
## keys in ~/.s3cfg and update the configuration file in ~/.s3cp
##
## This script is typically run from the root of ubuntu home.
## it will create a ~/bundle directory to store the resultant bundles
## that are uploaded to Amazon. 
##
## see ~/.bashrc - it should also contain your AWS credentials  as well!
## see ~/.bashrc - it should also contain your AWS credentials  as well!
## see ~/.bashrc - it should also contain your AWS credentials  as well!
## see ~/.bashrc - it should also contain your AWS credentials  as well!
##
## for destination buckets, please specify your region-specific S3 storage buckets.
##
## NOTE! The AWS Web interface has issues creating region-specific buckets.
## If you know your naming convention, simply let the AMI utilities automatically create
## your buckets for you by specifying a nice clear nomenclature.
## example:  export S3_ROOT_US_EAST_1=yourprefix-hpcc-us-east-1
## use dashes instead of underscores. 
#---------------------------------------------------------------------------
#
#

CMD_PREFIX=
[ "$USER" != "root"] && CMD_PREFIX=sudo

work_dir=$(dirname $0)
. ${work_dir}/lib/common

check_distro
. ${work_dir}/lib/common.${PKG_TYPE}


if [ ! -d ~/bundle ];
then
	echo "Creating ~/bundle directory..."
	mkdir ~/bundle
fi

export last_now=`ls -dt ~/bundle/* | head -1 | egrep -o '[0-9]+\-[0-9]+$'` 
export now=$(date -u +%Y%m%d-%H%M)

# see note above about buckets! you should let amazon create them for you as part of ami API.

if [ $# -lt 3 ];
then
        echo "ami-create.sh - script to create AMI from Ubuntu cloud standard AMIs"
        echo
        echo "usage: ami-create.sh newbuild|lastrun distro platformver buildnumber"
	echo "       newbuild means create NEW build of distro/platformver-buildnumber:"
        echo "       ami-create.sh newbuild precise 3.6.0 1"
        echo "       ami-create.sh newbuild precise 3.6.0 rc8"
	echo "       lastrun means resume last distro/platformver-buildnumber build where it left off"
        echo "       ami-create.sh lastrun precise 3.6.0 rc22"
	echo " "
        exit
fi

set -x

#if [ "$2" == "precise" ];
#then
#        echo "Sorry! I know precise was indicated as an option - it is not yet supported."
#        exit
#fi

# root_size is our resultant AMI root partition size after resize2fs of Ubuntu img file
# we specify a 10GB boot partition
# note we are only building a large ami at the moment
export root_size=10000M
export platformver=$3
export buildnumber=$4
export hpccversion=$platformver-$buildnumber
export codename=$2
export arch=${ARCH}
export tag=$(get_distro_version $DISTRO $codename)


if [ ! -e  ${work_dir}/lib/common.${DISTRO} ]
then
   echo "Unsupported distro ${DISTRO}. Only support Ubuntu and CentOS now"
   exit 1
else
   . ${work_dir}/lib/common.${DISTRO}
fi

get_image_site

echo $imagesite

export imagesite
#export imagetarfile=$codename-server-cloudimg-$arch.tar.gz


# Set certain variables
#export CLIENTTOOLS=hpccsystems-clienttools-community_${hpccversion}-noarch.deb
#export DOCUMENTATION=hpccsystems-documentation-community_${hpccversion}-noarch.deb
#export GRAPHCONTROL=hpccsystems-graphcontrol-community_${hpccversion}-noarch.deb
export PLATFORM=hpccsystems-platform-community_${hpccversion}${codename}_amd64.deb
export IFLOCATION=http://hpccsystems-installs.s3.amazonaws.com/communityedition/${codename}/

# AMI name timestamp

export last_now=`ls -t ~/bundle | grep $codename | head -1 | egrep -o '[0-9]+\-[0-9]+$'`
export now=$(date -u +%Y%m%d-%H%M)

if [ "$1" == "lastrun" -a "$last_now" != "" ];
then
        echo "Using lastrun timestamp..."
        export now=$last_now
else
        echo "No last run in ~/bundle for $codename - using $now..."
fi
# Turning on logging
exec > >(sudo sh -c "tee >> /var/log/ami-log-$codename-$now.log|logger -t ami-build -s 2>/dev/console") 2>&1

export imagetarfile=${DISTRO}-$tag-server-cloudimg-$arch.tar.gz
export imageurl=$imagesite/$imagetarfile
export bundlefn=hpccsystems-community-0${hpccversion}${codename}_${arch}-${now}
export name="hpcc-systems-community-$hpccversion-${DISTRO}-$tag-${codename}-amd64-$now"
export description="hpcc-systems Community $hpccversion ${DISTRO_DISPLAY_NAME} $release $tag ${codename^} $arch $now"

export image=/mnt/$bundlefn
export imagedir=/mnt/$codename-$arch

#==========================================================
if [ ! -f /mnt/$codename-server-cloudimg-$arch.img ];
then
	wget -O- $imageurl | sudo tar xzf - -C /mnt
	#cat $imagetarfile | sudo tar xzf - -C /mnt
fi

# each Amazon region has a different kernel-id. These are used later when bundling the image.
# we access the standard UBUNTU cloud image site to pull down the AMI IDs and regions.
# then we use the ec2-describe-images for each of the AMIs to grab the kernel-id used later when bundling and migrating

# home region is where the primary image is bundled.
# subsequent regions receive a migrated image built from this home bundle using an API command.
export EC2_HOME_REGION=us-east-1
#export S3_PREFIX=fln-hpcc
export S3_PREFIX=hpccsystems-amis

unset AMIS AKIS REGIONS S3BUCKETS RELEASE_AMIS
declare -a AMIS AKIS REGIONS S3BUCKETS RELEASE_AMIS

AMI=;AKI=;
IFSSAVE=$' \t\n'
IFS=$'\n'
#echo "curl --silent ${imagesite}"
echo "Get Ubuntu release AMIs"

get_release_amis
echo $RELEASE_AMIS



EC2_REGION_COUNT=0
for i in "${RELEASE_AMIS[@]}"; 
do
	echo $i
	REGION=`echo $i | grep -o "\-\-region [a-z]*-[a-z]*-[1-9]*" | sed "s/--region //g"` 
        # Skip eu-central-1. We will build eu-central-1 with script ami-create-one.sh
        [ "$REGION" = "eu-central-1" ] || [ "$REGION" = "ap-northeast-2" ] || [ "$REGION" = "us-gov-west-1" ] && continue
	echo "Found REGION $REGION"
	if [ $REGION == $EC2_HOME_REGION ];
	then
		AMI=`echo $i | grep -o "ami-[a-f0-9]*"`
		EC2_HOME_S3BUCKET="${S3_PREFIX}-$REGION"
		EC2_HOME_AMI=$AMI
		IFSTEMP=$IFS
		if [ -f $imagedir.aki.$REGION.xxxx ]
		then
			EC2_HOME_AKI=`cat $imagedir.aki.$REGION`
			echo "Read saved home AKI: $EC2_HOME_AKI from disk"
		else
			#IFS=$' \t\n' 
			#EC2_HOME_AKI=`ec2-describe-images $AMI --region $REGION | grep -o "aki-[a-f0-9]*"`
			#IFS=$IFSTEMP
			EC2_HOME_AKI=`echo $i | grep -o "aki-[a-f0-9]*"`
			echo "Saving home AKI $EC2_HOME_AKI to disk"
			echo $EC2_HOME_AKI | sudo tee $imagedir.aki.$REGION
		fi
	else

		[ "${REGIONS[$EC2_REGION_COUNT]}" = "$REGION" ] && continue

		EC2_REGION_COUNT=`expr $EC2_REGION_COUNT + 1`
		AMI=`echo $i | grep -o "ami-[a-f0-9]*"`
		AMIS[$EC2_REGION_COUNT]=$AMI
		REGIONS[$EC2_REGION_COUNT]=$REGION
		if [ -f $imagedir.aki.${REGION}.xxxx ]
		then
			AKI=`cat $imagedir.aki.$REGION`
			echo "Read saved $REGION AKI: $AKI from disk"
		else
			#IFSTEMP=$IFS 
			#IFS=$' \t\n' 
			#AKI=`ec2-describe-images $AMI --region $REGION | grep -o "aki-[a-f0-9]*"` 
			#IFS=$IFSTEMP
			AKI=`echo $i | grep -o "aki-[a-f0-9]*"` 
			echo "Saving $REGION AKI $AKI to disk"
			echo $AKI | sudo tee $imagedir.aki.$REGION
		fi
		AKIS[$EC2_REGION_COUNT]=$AKI
		S3BUCKETS[$EC2_REGION_COUNT]=${S3_PREFIX}-$REGION
	fi
done




# we now have our home AMI/AKI as well as the AMIs/AKIs for other available AWS regions
IFS=$IFSSAVE
export AMIS S3BUCKETS AKIS S3BUCKETS EC2_HOME_S3BUCKET EC2_HOME_AKI EC2_HOME_AMI EC2_REGION_COUNT REGIONS

set +x
echo "We found `expr $EC2_REGION_COUNT + 1` regions"
echo "Our home region: $EC2_HOME_REGION: $EC2_HOME_AMI $EC2_HOME_AKI $EC2_HOME_S3BUCKET"
echo ${REGIONS[*]}
echo ${AKIS[*]}
echo ${S3BUCKETS[*]}
for i in `seq 1 $EC2_REGION_COUNT`;
do 
	echo "${REGIONS[$i]}: ${AMIS[$i]} ${AKIS[$i]} ${S3BUCKETS[$i]}"
done

set -x

if [ ! -d ~/bundle/$bundlefn ]; 
then

sudo cp /mnt/$codename-server-cloudimg-$arch.img /mnt/$bundlefn


if [ "$4" != "minsize" ]; 
then
        echo "Resizing to 10GB for optimum AMI size."
	#here we resize our "EC2 image"
	sudo e2fsck -fy $image
	sudo resize2fs $image $root_size
	sudo e2fsck -fn $image

	echo "Resize done."
	export newimgsize=`du -m $image | cut -f1`
	echo "New image size: $newimgsize"
else
	echo "minsize parameter specified - keeping size the same as the ec2 cloud images"
fi

sudo mkdir -p $imagedir
sudo mount -o loop $image $imagedir

# Allow network access from chroot environment

for i in motd nologin vtrgb resolv.conf
do 
   [ -h $imagedir/etc/$i ] && sudo rm $imagedir/etc/$i
done
sudo cp -v /etc/resolv.conf $imagedir/etc/

# Fix what some consider to be a bug in vmbuilder
[ -e $imagedir/etc/hostname ] &&  sudo rm -f $imagedir/etc/hostname

# create empty /var/log/messages as 11.10 doesn't appear to include one
# and one-click fails without it
sudo touch $imagedir/var/log/messages

add_sources_list_multiverse

sudo chroot $imagedir mount -t proc none /proc
sudo chroot $imagedir mount -t devpts none /dev/pts

#sudo mount -t proc none $imagedir/proc
#sudo mount -t devpts none $imagedir/dev/pts

#sudo mount -t proc none $imagedir/proc

cat <<EOF | sudo tee $imagedir/usr/sbin/policy-rc.d > /dev/null
#!/bin/sh
exit 101
EOF
sudo chmod 755 $imagedir/usr/sbin/policy-rc.d

upgrade_pkg_sources

fix_chrooted_locale

echo 'Installing HPCC dependancies'


# s3fuse
#http://code.google.com/p/s3fs/wiki/InstallationNotes
#Install prerequisites before compiling:
#note some may already be installed (above) but for clarity list them again below

dependencies=$(cat ${work_dir}/dependencies/${codename})
install $dependencies

# Workaround JIRA HPCC ticket: HSIC-8
if [ "${codename}" = "trusty" ];
then 
   cat >> /etc/init/cloud-config.conf <<EOF
random_seed:
   command: ["pollinate", "-q", "--curl-opts", "-k"]
EOF
fi


#create install script on the fly in our chroot volume
sudo touch $imagedir/install_fuse.sh
sudo cat >> $imagedir/install_fuse.sh <<EOF
#!/bin/bash
cd /

#wget http://s3fs.googlecode.com/files/s3fs-1.61.tar.gz
#tar xvzf s3fs-1.61.tar.gz
#cd s3fs-1.61
#./configure --prefix=/usr
#make
#make install

# compiling from source is not working properly - grabbing sources from SVN
svn checkout http://s3fs.googlecode.com/svn/trunk/ s3fs
cd s3fs/
autoreconf --install
./configure --prefix=/usr
make
sudo make install
EOF

sudo chmod +x $imagedir/install_fuse.sh
sudo chroot $imagedir /install_fuse.sh

echo 'S3 Fuse now installed. See http://code.google.com/p/s3fs/wiki/FuseOverAmazon for usage'

echo 'Installing automation support for large cluster config'
install python-paramiko
install python-boto

echo 'Setting up hpcc user'

# Setting up user hpcc
sudo chroot $imagedir groupadd hpcc-test
sudo chroot $imagedir useradd -G hpcc-test hpcc

sudo chroot $imagedir mkdir -p /home/hpcc
sudo chroot $imagedir chown -R hpcc:hpcc-test /home/hpcc

echo 'User hpcc has been setup'

echo 'Installing hpcc platform '

# Set certain variables
export PLATFORM=hpccsystems-platform-community_${hpccversion}${codename}_${ARCH}.${PKG_TYPE}

#first location is amazon S3 but easier to just download directly from the hpccsystems.com site
#export IFLOCATION=https://s3.amazonaws.com/hpccsystems-installs/communityedition/${codename}/
export IFLOCATION=http://cdn.hpccsystems.com/releases/CE-Candidate-${platformver}/bin/platform/
#export IFLOCATION=http://10.176.32.10/builds/CE-Candidate-${platformver}/bin/platform/

sudo chroot $imagedir wget --progress=dot:mega --tries 5 $IFLOCATION$PLATFORM

install_from_local $PLATFORM     

sudo chroot $imagedir wget http://hpccsystems-installs.s3.amazonaws.com/communityedition/util/ips
sudo chroot $imagedir fromdos ips
sudo chroot $imagedir chmod +x ips
#sudo chroot $imagedir cp ips /opt/HPCCSystems/sbin

#echo 'Changing ownership of /mnt to hpcc user'
#sudo chroot $imagedir mkdir mnt
#sudo chroot $imagedir chown -R hpcc:hpcc /mnt/

echo 'Changing ownership HPCC directories'
sudo chroot $imagedir chown hpcc:hpcc -R /etc/HPCCSystems
sudo chroot $imagedir chown hpcc:hpcc -R /opt/HPCCSystems

sudo chroot $imagedir mkdir -p /var/lib/HPCCSystems
sudo chroot $imagedir mkdir -p /var/log/HPCCSystems
sudo chroot $imagedir chown -R hpcc:hpcc /var/lib/HPCCSystems
sudo chroot $imagedir chown -R hpcc:hpcc /var/log/HPCCSystems

#remove any ssh keys / deltritus that get installed as part of HPCC software
sudo find $imagedir | grep $imagedir/home | grep .ssh | xargs sudo rm -Rf
 
sudo rm -f $imagedir/usr/sbin/policy-rc.d

sudo chroot $imagedir umount /dev/pts
sudo chroot $imagedir umount proc

#sudo umount $imagedir/proc
sudo umount -d $imagedir

# hpccsystems-platform_community-3.4.2-1${codename}_amd64
#====================================================
fi # if user had specified lastrun and we had successfully built our chroot image and only wanted to rebundle/etc

mkdir -p ~/bundle/$bundlefn
echo 'Image built - please review.'


#################################################################################
# EC2_HOME_REGION - This is the location where the initial AMI is bundled for
# this is also the region where the EC2 instance exists that is running this script
#
# subsequent locations are simply migrated AMIs from this first created bundle
# First we bundle (only need on first AMI) then we upload and register
#################################################################################

unset HPCCAMIS
declare -a HPCCAMIS

if [ ! -f ~/$bundlefn.bundled ];
then
	ec2-bundle-image --batch --image $image --destination ~/bundle/$bundlefn --kernel $EC2_HOME_AKI -k $EC2_PRIVATE_KEY -c $EC2_CERT -u $EC2_ACCOUNT_ID
	touch ~/$bundlefn.bundled
	cp  ~/bundle/$bundlefn/$bundlefn.manifest.xml ~/bundle/$bundlefn/$bundlefn.manifest.xml.$EC2_HOME_REGION
fi

if [ ! -f ~/$bundlefn.uploaded.$EC2_HOME_REGION ];
then
	ec2-upload-bundle --batch --bucket $EC2_HOME_S3BUCKET --access-key $ACCESS_KEY --secret-key $SECRET_KEY --manifest ~/bundle/$bundlefn/$bundlefn.manifest.xml --retry
	touch ~/$bundlefn.uploaded.$EC2_HOME_REGION
fi

if [ ! -f ~/$bundlefn.registered.us-east-1 ];
then
	output_ami=`ec2-register $EC2_HOME_S3BUCKET/$bundlefn.manifest.xml --region $EC2_HOME_REGION -n "$name" --private-key $EC2_PRIVATE_KEY --cert $EC2_CERT | grep -o "ami-[a-f0-9]*"`
	echo $output_ami > $bundlefn.registered.$EC2_HOME_REGION
else
	output_ami=`cat $bundlefn.registered.$EC2_HOME_REGION`
fi
HPCCAMIS[0]=$output_ami
echo "Home (reference) $EC2_HOME_REGION AMI: $output_ami"
ec2-modify-image-attribute $output_ami -a all -l --region $EC2_HOME_REGION

#
# Now is the fun part. Remember the array of regions/kernel IDs we captured, above?
# Once we have the image bundled, uploaded, and registered for our "home region", we 
# use the ec2-migrate-image to automagically clone our home image to the other regions
#
# Here are the array indices in their typical order:
# 0: us-east-1
# 1: ap-northeast-1
# 2: ap-southeast-1
# 3: ap-southeast-2
# 4: eu-central-1
# 5: eu-west-1
# 6: sa-east-1
# 7: us-west-1
# 8: us-west-2


#
# Note! This next line is specifying which regions which AMIs to create
# This reference image is hard coded to ONLY create an AMI in your home region where this image is running.
# At this point in the script, there is an array of regions, with index zero being the HOME region.
#
# You will need to modify this next line with the for loop to migrate/bundle/upload/register in the other regions!
#
for i in `seq 1 $EC2_REGION_COUNT`;
#for i in `seq 99 $EC2_REGION_COUNT`;
do 
	echo "Migrating $EC2_HOME_REGION image to AWS region [$i] of [${EC2_REGION_COUNT}]:  ${REGIONS[$i]}: ${S3BUCKETS[$i]}"

	if [ ! -f ~/$bundlefn.migrated.${REGIONS[$i]} ];
	then
		ec2-migrate-manifest --kernel ${AKIS[$i]} --region ${REGIONS[$i]} --manifest ~/bundle/$bundlefn/$bundlefn.manifest.xml --privatekey $EC2_PRIVATE_KEY --cert $EC2_CERT --access-key $ACCESS_KEY --secret-key $SECRET_KEY
		touch ~/$bundlefn.migrated.${REGIONS[$i]}
		cp ~/bundle/$bundlefn/$bundlefn.manifest.xml ~/bundle/$bundlefn/$bundlefn.manifest.xml.${REGIONS[$i]}
		rm ~/bundle/$bundlefn/$bundlefn.manifest.xml.bak
	fi

	if [ ! -f ~/$bundlefn.uploaded.${REGIONS[$i]} ];
	then
		ec2-upload-bundle --batch --bucket ${S3BUCKETS[$i]} --access-key $ACCESS_KEY --secret-key $SECRET_KEY --manifest ~/bundle/$bundlefn/$bundlefn.manifest.xml --region ${REGIONS[$i]} --retry
		touch ~/$bundlefn.uploaded.${REGIONS[$i]}
	fi

	if [ ! -f ~/$bundlefn.registered.${REGIONS[$i]} ];
	then
		output_ami=`ec2-register ${S3BUCKETS[$i]}/$bundlefn.manifest.xml -n "$name" --region ${REGIONS[$i]} --private-key $EC2_PRIVATE_KEY --cert $EC2_CERT | grep -o "ami-[a-f0-9]*"`
		echo $output_ami > $bundlefn.registered.${REGIONS[$i]}
	else
		output_ami=`cat $bundlefn.registered.${REGIONS[$i]}`
	fi
	echo "${REGIONS[$i]} AMI: ${output_ami}"
	HPCCAMIS[$i]=$output_ami
	ec2-modify-image-attribute $output_ami -a all -l --region ${REGIONS[$i]}
done

#for i in `seq 0 $EC2_REGION_COUNT`;
#do 
#	echo "Making ${REGIONS[$i]} AMI:${HPCCAMIS[$i]} public..."
#	for j in ${EC2_SHARE_OWNER_IDS[*]};
#	do
#		ec2-modify-image-attribute ${HPCCAMIS[$i]} -a $j -l --region ${REGIONS[$i]}
#	done
#	ec2-modify-image-attribute ${HPCCAMIS[$i]} -a all -l --region ${REGIONS[$i]}
#done

echo 'AMI build complete. '
