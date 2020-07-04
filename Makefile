PROJECT_ID?=step-ca-a48ea0

export GOOGLE_APPLICATION_CREDENTIALS?=$(GOOGLE_APPLICATION_CREDENTIALS)


.PHONY: setup-kms
setup-kms:
	step-cloudkms-init -credentials-file=$$GOOGLE_APPLICATION_CREDENTIALS \
		-location=australia-southeast1 \
		-project=$(PROJECT_ID) \
		-ring=step-ca-keyring \
		-ssh

.PHONY: build-and-push
build-and-push:
	docker build -t asia.gcr.io/$(PROJECT_ID)/step-ca:stable .
	docker push asia.gcr.io/$(PROJECT_ID)/step-ca:stable