#!/bin/bash

#Set following two in profile no need provide them in EC2 Client tools
#Try ec2-describe-regions to test
#export AWS_ACCESS_KEY=AKIAJBNGGUQSU6NBXAKA
#export AWS_SECRET_KEY=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

#ec2-describe-regions
#ec2-describe-images --region us-east-1
##ec2-delete-disk-image -t <id> --region

#ec2-deregister
#ec2-delete-bundle


#S3
#s3cmd ls s3://juju-db76721c9dc364676405d1fd3d941f9e
#s3cmd del s3://juju-db76721c9dc364676405d1fd3d941f9e/*
#s3cmd rb s3://juju-db76721c9dc364676405d1fd3d941f9e
#

if [ -z "$1" ]; then
   echo "Must supply HPCC version"
   exit 1
fi
VERSION=$1

ACTION="list"

[ -n "$2" ] && ACTION=$2 

ACTION=$(echo $ACTION | tr '[:upper:]' '[:lower:]')

ec2-describe-regions | while read x region region2
do
    
    echo 
    echo "Process region $region ..."
    ec2-describe-images --region $region | while read name id image x
    do
        #echo "$name $id  $image"
        [ "$name" != "IMAGE" ] && continue
        echo $image |  grep -q "hpcc-systems-community-${VERSION}"
        if [ $? -eq 0 ]
        then
            if [ "$ACTION" = "delete" ]; then
               echo "ec2-deregister --region $region $id"
               ec2-deregister --region $region $id
            elif [ "$ACTION" = "list" ]; then
               echo "$id  $image"
            fi
        fi
    done
done
