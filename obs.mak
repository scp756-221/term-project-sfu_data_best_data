#
# Sub-make file to bring some sanity to the litany of tools and switches
# for installing Prometheus and Istio. This file adds a set of monitoring and
# observability tool including: Prometheus, Grafana and Kiali by way of installing
# them using Helm. Note the Helm repo is up-to-date as of mid-Nov 2020. 
#
# Prometheus, Grafana and Kiali are installed into the same namespace (istio-system)
# to make them work out-of-the-box (install). It may be possible to separate each of
# them out into their own namespace but I didn't have time to validate/explore this.
#
# The intended approach to working with this makefile is to update select
# elements (body, id, IP, port, etc) as you progress through your workflow.
# Where possible, stodout outputs are tee into .out files for later review.
#

KC=kubectl
DK=docker
HELM=helm

# Keep all the logs out of main directory
LOG_DIR=logs

# these might need to change
APP_NS=project-services
ISTIO_NS=istio-system
KIALI_OP_NS=kiali-operator

RELEASE=c756

# This might also change in step with Prometheus' evolution
PROMETHEUSPOD=prometheus-$(RELEASE)-kube-p-prometheus-0

all: install-prom install-kiali


# add the latest active repo for Prometheus
# Only needs to be done once for any user but is idempotent
init-helm:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts
	$(HELM) repo update

# note that the name $(RELEASE) is discretionary; it is used to reference the install 
# Grafana is included within this Prometheus package
install-prom:
	echo $(HELM) install $(RELEASE) --namespace $(ISTIO_NS) prometheus-community/kube-prometheus-stack
	$(HELM) install $(RELEASE) -f cluster/helm-kube-stack-values.yaml --namespace $(ISTIO_NS) prometheus-community/kube-prometheus-stack  || true
	$(KC) apply -n $(ISTIO_NS) -f cluster/monitoring-lb-services.yaml  || true
	$(KC) apply -n $(ISTIO_NS) -f cluster/grafana-flask-configmap.yaml  || true

uninstall-prom:
	echo $(HELM) uninstall $(RELEASE) --namespace $(ISTIO_NS)
	$(HELM) uninstall $(RELEASE) --namespace $(ISTIO_NS)

install-kiali:
	echo $(HELM) install --namespace $(ISTIO_NS) --set auth.strategy="anonymous" --repo https://kiali.org/helm-charts kiali-server kiali-server
	# This will fail every time after the first---the "|| true" suffix keeps Make running despite error
	$(KC) create namespace $(KIALI_OP_NS) || true
	$(HELM) install --set cr.create=true --set cr.namespace=$(ISTIO_NS) --namespace $(KIALI_OP_NS) --repo https://kiali.org/helm-charts kiali-operator kiali-operator || true
	$(KC) apply -n $(ISTIO_NS) -f cluster/kiali-cr.yaml

update-kiali:
	$(KC) apply -n $(ISTIO_NS) -f cluster/kiali-cr.yaml

uninstall-kiali:
	echo $(HELM) uninstall kiali-operator --namespace $(KIALI_OP_NS)
	$(HELM) uninstall kiali-operator --namespace $(KIALI_OP_NS)

status-kiali:
	$(KC) get -n $(ISTIO_NS) pod -l 'app=kiali'

promport:
	$(KC) describe pods $(PROMETHEUSPOD) -n $(ISTIO_NS)

extern: showcontext
	$(KC) -n $(ISTIO_NS) get svc istio-ingressgateway

# show deploy and pods in current ns; svc of cmpt756 ns
ls: showcontext
	$(KC) get gw,deployments,pods
	$(KC) -n $(APP_NS) get svc
	$(HELM) list -n $(ISTIO_NS)


# reminder of current context
showcontext:
	$(KC) config get-contexts
