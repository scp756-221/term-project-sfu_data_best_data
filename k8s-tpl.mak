#
# Front-end to bring some sanity to the litany of tools and switches
# for working with a k8s cluster. Note that this file exercise core k8s
# commands that's independent of the cluster vendor.
#
# All vendor-specific commands are in the make file for that vendor:
# az.mak, eks.mak, gcp.mak, mk.mak
#
# This file addresses APPPLing the Deployment, Service, Gateway, and VirtualService
#
# Be sure to set your context appropriately for the log monitor.
#
# The intended approach to working with this makefile is to update select
# elements (body, id, IP, port, etc) as you progress through your workflow.

# These will be filled in by template processor
CREG=ZZ-CR-ID
REGID=ZZ-REG-ID
AWS_REGION=ZZ-AWS-REGION

# Keep all the logs out of main directory
LOG_DIR=logs

# These should be in your search path
KC=kubectl
DK=docker
AWS=aws
IC=istioctl

# Application versions
# Override these by environment variables and `make -e`
APP_VER_TAG=v1
S2_VER=v1
LOADER_VER=v1

# Kubernetes parameters that most of the time will be unchanged
# but which you might override as projects become sophisticated
APP_NS=project-services
ISTIO_NS=istio-system

# this is used to switch M1 Mac to x86 for compatibility with x86 instances/students
ARCH=--platform x86_64


# ----------------------------------------------------------------------------------------
# -------  Targets to be invoked directly from command line                        -------
# ----------------------------------------------------------------------------------------

# ---  templates:  Instantiate all template files
#
# This is the only entry that *must* be run from k8s-tpl.mak
# (because it creates k8s.mak)
templates:
	tools/process-templates.sh

# --- provision: Provision the entire stack
# This typically is all you need to do to install the sample application and
# all its dependencies
#
# Preconditions:
# 1. Templates have been instantiated (make -f k8s-tpl.mak templates)
# 2. Current context is a running Kubernetes cluster (make -f {az,eks,gcp,mk}.mak start)
#
#  Nov 2021: Kiali is causing problems so do not deploy
provision: istio appns metric prom kiali deploy loader grafana-url prometheus-url kiali-url
#	Last step to scale istio-gateway to avoid crash on prometheus
	$(KC) scale deploy/istio-ingressgateway --replicas=30 -n $(ISTIO_NS)
#provision: istio prom deploy

# --- deploy: Deploy and monitor the three microservices
# Use `provision` to deploy the entire stack (including Istio, Prometheus, ...).
# This target only deploys the sample microservices
deploy: gw s1 s2 playlist db monitoring
	$(KC) -n $(APP_NS) get gw,vs,deploy,svc,pods

# --- rollout: Rollout new deployments of all microservices
rollout: rollout-s1 rollout-s2 rollout-pl rollout-db 

# --- rollout-s1: Rollout a new deployment of S1
rollout-s1: s1
	$(KC) rollout -n $(APP_NS) restart deployment/cmpt756s1

# --- rollout-s2: Rollout a new deployment of S2
rollout-s2: s2-docker  cluster/s2-dpl-$(S2_VER).yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-dpl-$(S2_VER).yaml
	$(KC) rollout -n $(APP_NS) restart deployment/cmpt756s2-$(S2_VER)

# --- rollout-playlist: Rollout a new deployment of playlist
rollout-pl: playlist
	$(KC) rollout -n $(APP_NS) restart deployment/playlist

# --- rollout-db: Rollout a new deployment of DB
rollout-db: db
	$(KC) rollout -n $(APP_NS) restart deployment/cmpt756db

# --- health-off: Turn off the health monitoring for the three microservices
# If you don't know exactly why you want to do this---don't
health-off:
	$(KC) -n $(APP_NS) apply -f cluster/s1-nohealth.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-nohealth.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db-nohealth.yaml

# --- scratch: Delete the microservices and everything else in application NS
scratch: dynamodb-clean
	$(KC) delete -n $(APP_NS) deploy --all
	$(KC) delete -n $(APP_NS) svc    --all
	$(KC) delete -n $(APP_NS) gw     --all
	$(KC) delete -n $(APP_NS) dr     --all
	$(KC) delete -n $(APP_NS) vs     --all
	$(KC) delete -n $(APP_NS) se     --all
	$(KC) delete -n $(APP_NS) --ignore-not-found=true jobs/cmpt756loader
	$(KC) delete hpa cmpt756db --ignore-not-found=true
	$(KC) delete hpa cmpt756s1 --ignore-not-found=true
	$(KC) delete hpa cmpt756s2-$(S2_VER) --ignore-not-found=true
	$(KC) delete hpa playlist --ignore-not-found=true
	$(KC) delete -n $(ISTIO_NS) vs monitoring --ignore-not-found=true
	$(KC) get -n $(APP_NS) deploy,svc,pods,gw,dr,vs,se
	$(KC) get -n $(ISTIO_NS) vs

# --- dashboard: Start the standard Kubernetes dashboard
# NOTE:  Before invoking this, the dashboard must be installed and a service account created
dashboard: showcontext
	echo Please follow instructions at https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html
	echo Remember to 'pkill kubectl' when you are done!
	$(KC) proxy &
	open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login

# --- extern: Display status of Istio ingress gateway
# Especially useful for Minikube, if you can't remember whether you invoked its `lb`
# target or directly ran `minikube tunnel`
extern: showcontext
	$(KC) -n $(ISTIO_NS) get svc istio-ingressgateway

# --- log-X: show the log of a particular service
log-s1:
	$(KC) -n $(APP_NS) logs deployment/cmpt756s1 --container cmpt756s1

log-s2:
	$(KC) -n $(APP_NS) logs deployment/cmpt756s2 --container cmpt756s2

log-db:
	$(KC) -n $(APP_NS) logs deployment/cmpt756db --container cmpt756db


# --- shell-X: hint for shell into a particular service
shell-s1:
	@echo Use the following command line to drop into the s1 service:
	@echo   $(KC) -n $(APP_NS) exec -it deployment/cmpt756s1 --container cmpt756s1 -- bash

shell-s2:
	@echo Use the following command line to drop into the s2 service:
	@echo   $(KC) -n $(APP_NS) exec -it deployment/cmpt756s2 --container cmpt756s2 -- bash

shell-db:
	@echo Use the following command line to drop into the db service:
	@echo   $(KC) -n $(APP_NS) exec -it deployment/cmpt756db --container cmpt756db -- bash

# --- lsa: List services in all namespaces
lsa: showcontext
	$(KC) get svc --all-namespaces

# --- ls: Show deploy, pods, vs, and svc of application ns
ls: showcontext
	$(KC) get -n $(APP_NS) gw,vs,svc,deployments,pods

# --- lsd: Show containers in pods for all namespaces
lsd:
	$(KC) get pods --all-namespaces -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' | sort

# --- reinstate: Reinstate provisioning on a new set of worker nodes
# Do this after you do `up` on a cluster that implements that operation.
# AWS implements `up` and `down`; other cloud vendors may not.
reinstate: istio
	$(KC) create ns $(APP_NS)
	$(KC) label ns $(APP_NS) istio-injection=enabled

# --- showcontext: Display current context
showcontext:
	$(KC) config get-contexts

# Run the loader, rebuilding if necessary, starting DynamDB if necessary, building ConfigMaps
loader: dynamodb-init ac-db loader-docker cluster/loader.yaml
	$(KC) -n $(APP_NS) delete --ignore-not-found=true jobs/cmpt756loader
	tools/build-configmap.sh gatling/resources/users.csv cluster/users-header.yaml | kubectl -n $(APP_NS) apply -f -
	tools/build-configmap.sh gatling/resources/music.csv cluster/music-header.yaml | kubectl -n $(APP_NS) apply -f -
	tools/build-configmap.sh gatling/resources/playlist.csv cluster/playlist-header.yaml | kubectl -n $(APP_NS) apply -f -
	$(KC) -n $(APP_NS) apply -f cluster/loader.yaml

# --- dynamodb-init: set up our DynamoDB tables
#
dynamodb-init: cluster/cloudformationdynamodb.json
# Start DynamoDB at the default read and write rates
	@# "|| true" suffix because command fails when stack already exists
	@# (even with --on-failure DO_NOTHING, a nonzero error code is returned)
	$(AWS) cloudformation create-stack --stack-name db-ZZ-REG-ID --template-body file://$< || true
	# Must give DynamoDB time to create the tables before running the loader
	sleep 20

# --- dynamodb-stop: Stop the AWS DynamoDB service
#
dynamodb-clean:
	$(AWS) cloudformation delete-stack --stack-name db-ZZ-REG-ID || true

# --- ls-tables: List the tables and their read/write units for all DynamodDB tables
ls-tables:
	@tools/list-dynamodb-tables.sh $(AWS) $(AWS_REGION)

# --- registry-login: Login to the container registry
#
registry-login:
	@/bin/sh -c 'cat cluster/${CREG}-token.txt | $(DK) login $(CREG) -u $(REGID) --password-stdin'

# --- Variables defined for URL targets
# Utility to get the hostname (AWS) or ip (everyone else) of a load-balanced service
# Must be followed by a service
IP_GET_CMD=tools/getip.sh $(KC) $(ISTIO_NS)

# This expression is reused several times
# Use back-tick for subshell so as not to confuse with make $() variable notation
INGRESS_IP=`$(IP_GET_CMD) svc/istio-ingressgateway`

# --- kiali-url: Print the URL to browse Kiali in current cluster
kiali-url:
	@/bin/sh -c 'echo http://$(INGRESS_IP)/kiali'

# --- grafana-url: Print the URL to browse Grafana in current cluster
grafana-url:
	@# Use back-tick for subshell so as not to confuse with make $() variable notation
	@/bin/sh -c 'echo http://`$(IP_GET_CMD) svc/grafana-ingress`:3000/'

# --- prometheus-url: Print the URL to browse Prometheus in current cluster
prometheus-url:
	@# Use back-tick for subshell so as not to confuse with make $() variable notation
	@/bin/sh -c 'echo http://`$(IP_GET_CMD) svc/prom-ingress`:9090/'


# ----------------------------------------------------------------------------------------
# ------- Targets called by above. Not normally invoked directly from command line -------
# ------- Note that some subtargets are in `obs.mak`                               -------
# ----------------------------------------------------------------------------------------

# Install Prometheus stack by calling `obs.mak` recursively
prom:
	make -f obs.mak init-helm --no-print-directory
	make -f obs.mak install-prom --no-print-directory

# Install Kiali operator and Kiali by calling `obs.mak` recursively
# Waits for Kiali to be created and begin running. This wait is required
# before installing the three microservices because they
# depend upon some Custom Resource Definitions (CRDs) added
# by Kiali
kiali:
	make -f obs.mak install-kiali
	# Kiali operator can take awhile to start Kiali
	tools/waiteq.sh 'app=kiali' '{.items[*]}'              ''        'Kiali' 'Created'
	tools/waitne.sh 'app=kiali' '{.items[0].status.phase}' 'Running' 'Kiali' 'Running'

# Install Istio
istio:
	$(IC) install -y --set profile=demo --set hub=gcr.io/istio-release

# Create and configure the application namespace
appns: cluster/namespace.yaml
	# Appended "|| true" so that make continues even when command fails
	# because namespace already exists
	# $(KC) create ns $(APP_NS) || true
	$(KC) apply -f cluster/namespace.yaml
	$(KC) config set-context aws756 --namespace=$(APP_NS)
	$(KC) label namespace $(APP_NS) --overwrite=true istio-injection=enabled

# Update monitoring virtual service and display result
monitoring: monvs
	$(KC) -n $(ISTIO_NS) get vs

# Update monitoring virtual service
monvs: cluster/monitoring-virtualservice.yaml
	$(KC) -n $(ISTIO_NS) apply -f $<

# Update service gateway
gw: cluster/service-gateway.yaml
	$(KC) -n $(APP_NS) apply -f $< 
	$(KC) scale deploy/istio-ingressgateway --replicas=1 -n $(ISTIO_NS) || true
	$(KC) autoscale deploy/istio-egressgateway --cpu-percent=90 --min=1 --max=20 -n $(ISTIO_NS) || true

# Update S1 and associated monitoring, rebuilding if necessary
s1: s1-docker cluster/s1.yaml cluster/s1-sm.yaml cluster/s1-vs.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s1.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s1-sm.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s1-vs.yaml
	$(KC) delete hpa cmpt756s1 || true
	$(KC) autoscale deploy/cmpt756s1 --cpu-percent=80 --min=35 --max=430|| true

# Update S2 and associated monitoring, rebuilding if necessary
s2: rollout-s2 cluster/s2-svc.yaml cluster/s2-sm.yaml cluster/s2-vs.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-svc.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-sm.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-vs.yaml
	$(KC) delete hpa cmpt756s2-$(S2_VER) || true
	$(KC) autoscale deploy/cmpt756s2-$(S2_VER) --cpu-percent=80 --min=35 --max=430|| true

playlist: playlist-docker playlist/Dockerfile playlist/app.py playlist/requirements.txt
	$(KC) -n $(APP_NS) apply -f cluster/playlist.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-sm.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs.yaml
	$(KC) delete hpa playlist || true
	$(KC) autoscale deploy/playlist --cpu-percent=80 --min=35 --max=430|| true

# Update DB and associated monitoring, rebuilding if necessary
db: db-docker cluster/awscred.yaml cluster/dynamodb-service-entry.yaml cluster/db.yaml cluster/db-sm.yaml cluster/db-vs.yaml
	$(KC) -n $(APP_NS) apply -f cluster/awscred.yaml
	$(KC) -n $(APP_NS) apply -f cluster/dynamodb-service-entry.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db-sm.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db-vs.yaml
	$(KC) delete hpa cmpt756db || true
	$(KC) autoscale deploy/cmpt756db --cpu-percent=80 --min=100 --max=500|| true

# Build & push the images up to the CR
cri: s1-docker s2-docker playlist-docker db-docker

# Build the s1 service
s1-docker: s1/Dockerfile s1/app.py s1/requirements.txt
	make -f k8s.mak --no-print-directory registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/cmpt756s1:$(APP_VER_TAG) s1
	$(DK) push $(CREG)/$(REGID)/cmpt756s1:$(APP_VER_TAG)

# Build the s2 service
s2-docker: s2/$(S2_VER)/Dockerfile s2/$(S2_VER)/app.py s2/$(S2_VER)/requirements.txt
	make -f k8s.mak --no-print-directory registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/cmpt756s2:$(S2_VER) s2/$(S2_VER)
	$(DK) push $(CREG)/$(REGID)/cmpt756s2:$(S2_VER)

# Build the playlist service
playlist-docker: playlist/Dockerfile playlist/app.py playlist/requirements.txt
	make -f k8s.mak --no-print-directory registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/playlist:$(APP_VER_TAG) playlist
	$(DK) push $(CREG)/$(REGID)/playlist:$(APP_VER_TAG)

# Build the db service
db-docker: db/Dockerfile db/app.py db/requirements.txt
	make -f k8s.mak --no-print-directory registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/cmpt756db:$(APP_VER_TAG) db
	$(DK) push $(CREG)/$(REGID)/cmpt756db:$(APP_VER_TAG)

# Build the loader
loader-docker: loader/app.py loader/requirements.txt loader/Dockerfile registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/cmpt756loader:$(LOADER_VER) loader
	$(DK) push $(CREG)/$(REGID)/cmpt756loader:$(LOADER_VER)

# Push all the container images to the container registry
# This isn't often used because the individual build targets also push
# the updated images to the registry
cr: registry-login
	$(DK) push $(CREG)/$(REGID)/cmpt756s1:$(APP_VER_TAG)
	$(DK) push $(CREG)/$(REGID)/cmpt756s2:$(S2_VER)
	$(DK) push $(CREG)/$(REGID)/cmpt756db:$(APP_VER_TAG)

# ---------------------------------------------------------------------------------------
# Handy bits for exploring the container images... not necessary
image: showcontext registry-login
	$(DK) image ls | tee __header | grep $(REGID) > __content
	head -n 1 __header
	cat __content
	rm __content __header

# Create a scalable target for DynamoDB tables
ac-db: cluster/scaling-policy.json
	$(AWS) application-autoscaling register-scalable-target \
		--service-namespace dynamodb \
		--resource-id "table/Playlist-$(REGID)" \
		--scalable-dimension "dynamodb:table:ReadCapacityUnits" \
		--min-capacity 5000 \
		--max-capacity 10000
	$(AWS) application-autoscaling register-scalable-target \
		--service-namespace dynamodb \
		--resource-id "table/User-$(REGID)" \
		--scalable-dimension "dynamodb:table:ReadCapacityUnits" \
		--min-capacity 5000 \
		--max-capacity 10000
	$(AWS) application-autoscaling register-scalable-target \
		--service-namespace dynamodb \
		--resource-id "table/Music-$(REGID)" \
		--scalable-dimension "dynamodb:table:ReadCapacityUnits" \
		--min-capacity 5000 \
		--max-capacity 10000
	$(AWS) application-autoscaling put-scaling-policy \
		--service-namespace dynamodb \
		--resource-id "table/Playlist-$(REGID)" \
		--scalable-dimension "dynamodb:table:ReadCapacityUnits" \
		--policy-name "ScalingPolicy" \
		--policy-type "TargetTrackingScaling" \
		--target-tracking-scaling-policy-configuration file://$<
	$(AWS) application-autoscaling put-scaling-policy \
		--service-namespace dynamodb \
		--resource-id "table/User-$(REGID)" \
		--scalable-dimension "dynamodb:table:ReadCapacityUnits" \
		--policy-name "ScalingPolicy" \
		--policy-type "TargetTrackingScaling" \
		--target-tracking-scaling-policy-configuration file://$<
	$(AWS) application-autoscaling put-scaling-policy \
		--service-namespace dynamodb \
		--resource-id "table/Music-$(REGID)" \
		--scalable-dimension "dynamodb:table:ReadCapacityUnits" \
		--policy-name "ScalingPolicy" \
		--policy-type "TargetTrackingScaling" \
		--target-tracking-scaling-policy-configuration file://$<

#==========Metric Server===========
metric:
	$(KC) apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	$(KC) get deployment metrics-server -n kube-system


#==========For failure remediation===========
provision-delay: cluster/db-vs-delay.yaml cluster/playlist-vs-delay.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db-vs-delay.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-delay.yaml

provision-abort: cluster/db-vs-abort.yaml cluster/playlist-vs-abort.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db-vs-abort.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-abort.yaml

provision-circuit: cluster/playlist-vs-circuit.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-circuit.yaml

playlist-1: playlist/Dockerfile playlist/app.py playlist/requirements.txt
	make -f k8s.mak --no-print-directory registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/playlist:v1 playlist
	$(DK) push $(CREG)/$(REGID)/playlist:v1

playlist-2: playlist/v2/Dockerfile playlist/v2/app.py playlist/v2/requirements.txt
	make -f k8s.mak --no-print-directory registry-login
	$(DK) build $(ARCH) -t $(CREG)/$(REGID)/playlist:v2 playlist/v2
	$(DK) push $(CREG)/$(REGID)/playlist:v2

rollout-playlist-1: playlist-1 cluster/playlist1.yaml
	$(KC) delete deployments playlist || true
	$(KC) -n $(APP_NS) apply -f cluster/playlist1.yaml
	$(KC) rollout -n $(APP_NS) restart deployment/playlist-v1
	$(KC) delete hpa playlist-v1 || true
	$(KC) autoscale deploy/playlist-v1 --cpu-percent=80 --min=35 --max=430|| true

rollout-playlist-2: playlist-2 cluster/playlist2.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist2.yaml
	$(KC) rollout -n $(APP_NS) restart deployment/playlist-v2
	$(KC) delete hpa playlist-v2 || true
	$(KC) autoscale deploy/playlist-v2 --cpu-percent=80 --min=35 --max=430|| true

provision-canary: rollout-playlist-1 rollout-playlist-2 cluster/playlist.yaml cluster/playlist-sm.yaml cluster/playlist-vs-canary.yaml cluster/playlist-svc.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-sm.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-svc.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-canary.yaml
	
	$(KC) delete hpa playlist || true

reroute-playlist-1: cluster/playlist-vs-canary-reroute.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-canary-reroute.yaml

reroute-playlist: rollout-playlist-2 cluster/playlist-vs-canary.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-canary.yaml

reroute-playlist-2: cluster/playlist-vs-canary.yaml
	$(KC) -n $(APP_NS) apply -f cluster/playlist-vs-canary.yaml
