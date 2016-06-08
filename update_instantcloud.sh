#!/bin/bash

script_name=$(basename $0)
script_dir=$(dirname $0)

function usage()
{
   echo ""
   echo "${script_name} -a <ami file> -s <settings file> -v <version> "
   echo "      -b <backup dir>  -l <distro>"
   echo ""
   exit 0
}

ami_list=
distro_codename=precise
hpcc_version=
#settings_file=~/sites/cloud/settings_base.py
settings_file=./settings_base.py
backup_dir=
while getopts "*ha:b:l:s:v:" arg
do
   case $arg in
      a) ami_list=$OPTARG
         ;;
      b) backup_dir=$OPTARG
         ;;
      l) distro_codename=$OPTARG
         ;;
      s) settings_file=$OPTARG
         ;;
      v) hpcc_version=$OPTARG
         ;;
      h|?) usage
         ;;
   esac
done

#echo $script_name
[ -z "$ami_list" ] && usage
[ -z "$hpcc_version" ] && usage

regions=(
   'eu-west-1'
   'ap-southeast-1'
   'ap-southeast-2'
   'eu-central-1'
   'ap-northeast-1'
   'us-east-1'
   'sa-east-1'
   'us-west-1'
   'us-west-2'
)  

#------------------------------------------
# Get AMIs from version and Linux distro
# code name
#------------------------------------------
declare -A AMIS
i=0
action=search_region
while read line
do
 [ -z "$line" ] && continue
 if [ "$action" = "search_region" ]
 then
     echo $line | grep -q ${regions[$i]} 
     [ $? -ne 0 ] && continue
     action="search_ami"
     current_region=${regions[$i]}
     i=$(expr $i \+ 1)
 elif [ "$action" = "search_ami" ]
 then
     echo $line | grep "$hpcc-version" | grep -q "$distro_codename"
     [ $? -ne 0 ] && continue
     AMIS["$current_region"]=$(echo $line | cut -d' ' -f1)
     if [ $i -eq ${#regions[*]} ] 
     then
        action="done"
        break
     fi
     action=search_region
 fi
done < $ami_list

if [ "$action" != "done" ]
then
   if [ "$action" = "search_region" ]
   then
       echo "Could not find region ${regions[$i]}"
   elif [ "$action" = "search_ami" ]
   then
       echo "Could not find ami for region ${regions[$i]}"
   fi
   exit 1
fi

#echo "AMIS ..."

#------------------------------------------
# Substitute AMIs in settings_base.py
#------------------------------------------
[ -z "$backup_dir" ] && backup_dir=$(dirname $settings_file)
settings_file_name=$(basename $settings_file)
DATE_TIME=$(date "+%Y-%m-%d_%H-%M-%S")
cp ${settings_file} ${backup_dir}/${settings_file_name}_$DATE_TIME

for region in "${!AMIS[@]}"
do
    echo "$region :  ${AMIS[$region]}"
    sed -i.bk  "/${region}_m[[:digit:]]\.large_instance/ { 
       N
       s/'ami'[[:space:]]*:.*/'ami'\: '${AMIS[$region]}',/
    }" $settings_file 

done 

#    sed -i.bk  "/${region}_m[[:digit:]]\.large_instance/, /hpcc_global_memoery_size.*$/ { 

sed -i.bk "s/'hpcc'[[:space:]]*:.*/'hpcc': '${hpcc_version}'/"  $settings_file 
#mv /tmp/settings_file_$$ settings_file

# This backup is useless
[ -e ${settings_file}.bk ] && rm -rf ${settings_file}.bk

#------------------------------------------
# restart apache
#------------------------------------------
echo "Restart apache httpd"
echo "On development system:  sudo /usr/sbin/apache2ctl restart"
echo "On product system:  sudo service apache2 stop"
echo "                    sudo service apache2 start"
echo ""
