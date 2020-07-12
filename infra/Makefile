.PHONY: all clean test

PROJECT_ID?=step-ca-410ca8
TF_STATE_BUCKET?=$(PROJECT_ID)-terraform-state


.PHONY: init
init:
	terraform init -backend-config=bucket=$(TF_STATE_BUCKET) -reconfigure

.PHONY: ssh
ssh:
	gcloud --project $(PROJECT_ID) compute ssh "$$(gcloud --project $(PROJECT_ID) compute instance-groups list-instances ca-mig --zone australia-southeast1-c --format="value(NAME)")" \
		--tunnel-through-iap --zone australia-southeast1-c
