PROJECT_ID?=step-ca-a48ea0
STEP_CERTS_VERSION?=0.14.6

export GOOGLE_APPLICATION_CREDENTIALS?=$(GOOGLE_APPLICATION_CREDENTIALS)


.PHONY: setup-kms
setup-kms:
	step-cloudkms-init -credentials-file=$$GOOGLE_APPLICATION_CREDENTIALS \
		-location=australia-southeast1 \
		-project=$(PROJECT_ID) \
		-ring=step-ca-keyring \
		-ssh

.PHONY: build
build:
	docker build \
		--build-arg STEP_CERTS_VERSION=$(STEP_CERTS_VERSION) \
		-t asia.gcr.io/$(PROJECT_ID)/step-ca:$(STEP_CERTS_VERSION) .

.PHONY: build-and-push
build-and-push: build
	docker push asia.gcr.io/$(PROJECT_ID)/step-ca:$(STEP_CERTS_VERSION)
