#! /bin/bash
set -ex

if [ "$1" = 'step-ca' ]; then
	# retrieve the current project ID from GCP metadata API
	PROJECT_ID="$(curl http://metadata.google.internal/computeMetadata/v1/project/project-id -H Metadata-Flavor:Google)"

	# extract CA configuration file
	gcloud --project "$PROJECT_ID" secrets versions access 15 --secret=step-ca-config > /root/.step/config/ca.json

	# extract root and intermediate certs
	gcloud --project "$PROJECT_ID" secrets versions access 1 --secret=root-crt > /root/.step/certs/root_ca.crt
	gcloud --project "$PROJECT_ID" secrets versions access 1 --secret=intermediate-crt > /root/.step/certs/intermediate_ca.crt
fi

exec "$@"
