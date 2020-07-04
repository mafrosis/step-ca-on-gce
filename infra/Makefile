.PHONY: all clean test

PROJECT_ID?=step-ca-410ca8
TF_STATE_BUCKET?=$(PROJECT_ID)-terraform-state


.PHONY: init
init:
	terraform init -backend-config=bucket=$(TF_STATE_BUCKET) -reconfigure
