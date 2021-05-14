SHELL := /usr/bin/env bash

IMAGE_REGISTRY ?= quay.io
IMAGE_REPOSITORY ?= app-sre
QUAY_USER ?=
QUAY_TOKEN ?=
CONTAINER_ENGINE_CONFIG_DIR = .docker

# Accommodate docker or podman
CONTAINER_ENGINE=$(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)

FORWARDER_VERSION=$(shell cat .splunk-version)
FORWARDER_HASH=$(shell cat .splunk-version-hash)

FORWARDER_NAME=splunk-forwarder
FORWARDER_IMAGE_URI=$(IMAGE_REGISTRY)/$(IMAGE_REPOSITORY)/$(FORWARDER_NAME):$(FORWARDER_VERSION)-$(FORWARDER_HASH)
FORWARDER_DOCKERFILE = ./containers/forwarder/Dockerfile

HEAVYFORWARDER_NAME=splunk-heavyforwarder
HEAVYFORWARDER_IMAGE_URI=$(IMAGE_REGISTRY)/$(IMAGE_REPOSITORY)/$(HEAVYFORWARDER_NAME):$(FORWARDER_VERSION)-$(FORWARDER_HASH)
HEAVYFORWARDER_DOCKERFILE = ./containers/heavy_forwarder/Dockerfile

.PHONY: build-forwarder
build-forwarder:
	$(CONTAINER_ENGINE) build . -f $(FORWARDER_DOCKERFILE) -t $(FORWARDER_IMAGE_URI)

.PHONY: build-heavyforwarder
build-heavyforwarder:
	$(CONTAINER_ENGINE) build . -f $(HEAVYFORWARDER_DOCKERFILE) -t $(HEAVYFORWARDER_IMAGE_URI)

.PHONY: push-forwarder
push-forwarder:
	skopeo copy --dest-creds "$(QUAY_USER):$(QUAY_TOKEN)" "docker-daemon:$(FORWARDER_IMAGE_URI)" "docker://$(FORWARDER_IMAGE_URI)"

# Use caution: this is huge
.PHONY: push-heavyforwarder
push-heavyforwarder:
	skopeo copy --dest-creds "$(QUAY_USER):$(QUAY_TOKEN)" "docker-daemon:$(HEAVYFORWARDER_IMAGE_URI)" "docker://$(HEAVYFORWARDER_IMAGE_URI)"

.PHONY: vuln-check
vuln-check: build-forwarder build-heavyforwarder
	./hack/check-image-against-osd-sre-clair.sh $(FORWARDER_IMAGE_URI)
	./hack/check-image-against-osd-sre-clair.sh $(HEAVYFORWARDER_IMAGE_URI)

##################
### Used by CD >>>
.PHONY: build-push
build-push: docker-login
	./hack/app-sre-build-push.sh "$(FORWARDER_IMAGE_URI)" "$(FORWARDER_DOCKERFILE)"
	./hack/app-sre-build-push.sh "$(HEAVYFORWARDER_IMAGE_URI)" "$(HEAVYFORWARDER_DOCKERFILE)"

.PHONY: docker-login
docker-login:
	@test "${QUAY_USER}" != "" && test "${QUAY_TOKEN}" != "" || (echo "QUAY_USER and QUAY_TOKEN must be defined" && exit 1)
	@mkdir -p ${CONTAINER_ENGINE_CONFIG_DIR}
	@${CONTAINER_ENGINE} --config=${CONTAINER_ENGINE_CONFIG_DIR} login -u="${QUAY_USER}" -p="${QUAY_TOKEN}" quay.io

.PHONY: docker-build-push-one
docker-build-push-one:
	@(if [[ -z "${IMAGE_URI}" ]]; then echo "Must specify IMAGE_URI"; exit 1; fi)
	@(if [[ -z "${DOCKERFILE_PATH}" ]]; then echo "Must specify DOCKERFILE_PATH"; exit 1; fi)
	${CONTAINER_ENGINE} build . -f $(DOCKERFILE_PATH) -t $(IMAGE_URI)
	${CONTAINER_ENGINE} --config=${CONTAINER_ENGINE_CONFIG_DIR} push ${IMAGE_URI}
### <<< Used by CD
##################
