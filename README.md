# SFU_Data_Best_Data project directory

This is the project repo for CMPT 756 (Spring 2022)

### 1. Prerequisites

#### Prepare AWS account, key, secret creation, service role

#### Complete AWS CLI configuration

#### Prepare Github account, PAT

#### git local config configuration

#### Prepare EC2 key

#### Install relevant tools such as eksctl, istioctl, k9s, jq, helm

#### Run below command to get repo
~~~
$ git clone https://github.com/scp756-221/term-project-sfu_data_best_data.git
$ cd term-project-sfu_data_best_data
$ make -f k8s.mak dynamodb-clean
~~~

### Fill in the required values in the template variable file

Copy the file `cluster/tpl-vars-blank.txt` to `cluster/tpl-vars.txt`
and fill in all the required values in `tpl-vars.txt`.  These include
things like your AWS keys, your GitHub signon, and other identifying
information.

Create the file `cluster/ghcr.io-token.txt` and put your github account PAT in it.

### Instantiate the templates

Once you have filled in all the details, run

~~~
$ make -f k8s-tpl.mak templates
~~~

### Startup AWS EKS cluster
Run

~~~
$ make -f eks.mak start
~~~

### Install everything in empty cluster
Run

~~~
$ make -f k8s.mak provision
~~~
Then check the Dynamodb table status from AWS console, they maybe still show'updating' and need to wait until it's done.

### Run your thing
#### Run client
~~~
$ kubectl -n istio-system get service istio-ingressgateway | cut -c -140
$ cd mcli
$ make build-mcli
$ make PORT=80 SERVER=<SERVER HOSTNAME> SERVICE=<user or music or playlist> run-mcli
~~~

#### Run simulators on EC2
Modify the file `profile/ec2.mak` to add segments `SGI_WFH`, `SGRI_WFH`, `KEY`, and `LKEY`. Then run

~~~
$ source profile/aws-a
$ erun
$ essh
EC2$ git clone https://github.com/scp756-221/term-project-sfu_data_best_data.git
EC2$ cd term-project-sfu_data_best_data/
EC2$ chmod 755 ec2-gatling-pre.sh
EC2$ ./ec2-gatling-pre.sh
EC2$ ./gatling-1000.sh
~~~