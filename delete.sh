#!/bin/sh

if [ -z "$1" ]; then
   echo "Must provide a version to delete"
fi


./s3.sh  $1 delete
./ami_cli.sh  $1 delete
