# HPCC-AMI-Builds
HPCC AMI builds for Amazon EC2

## Build HPCC AMIs
1. cd to build directory
2. Build all region except eu-central: ./ami-create.sh newbuild <precise|trusty> <version> <build sequence>
   For example, on Ubuntu 14.04 amd64 build system: ./ami-create.sh newbuild trusty 5.2.4 1
3. Build for eu-central: ./ami-create-one.sh newbuild <precise|trusty> <version> <build sequence>
   For example, on Ubuntu 14.04 amd64 build system: ./ami-create-one.sh newbuild trusty 5.2.4 1

## Manage HPCC AMIs
1. Check AMIs: ./ami_cli.sh <version>
2. Delete AMIs: ./ami_cli.sh <version> delete
3. Check S3 storage: ./s3.sh <version>
4. Delete S3 storage: ./s3.sh <version> delete
