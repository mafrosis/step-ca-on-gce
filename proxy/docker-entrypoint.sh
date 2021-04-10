#! /bin/bash
set -e


if [ "$1" = 'nginx' ]; then
	if [ "$DEBUG" ]; then
		set -x
	fi

	if [ ! -f /tmp/provisioner.key ]; then
		# extract provisioner private key
		OAUTH_TOKEN="$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" -H "Metadata-Flavor: Google" | jq -r .access_token)"

		# use curl rather than gcloud to retrieve the secret, as curl is MUCH faster
		curl -s "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/proxy-provisioner-pk/versions/1:access" \
			--request "GET" \
			--header "authorization: Bearer ${OAUTH_TOKEN}" \
			--header "content-type: application/json" \
			--header "x-goog-user-project: ${PROJECT_ID}" \
			| jq -r ".payload.data" | base64 -d \
			> /tmp/provisioner.key
	fi

	if [ -z ${INSTANCE+x} ]; then
		# retrieve instance name of GCE VM
		INSTANCE="$(${GCLOUD} compute instance-groups list-instances ca-mig --zone australia-southeast1-c --format="value(NAME)")"
	fi

	if [ -z ${IP+x} ]; then
		# retrieve instance private IP from internal DNS name
		IP="$(dig +short "$INSTANCE.australia-southeast1-c.c.$PROJECT_ID.internal")"
	fi

	# create local DNS entry for CA server private IP
	echo "$IP ca.mafro.internal" >> /etc/hosts
	nc -vz ca.mafro.internal 443

	# generate a one-time-token using the private key
	TOKEN=$(step ca token "$PROJECT_ID" --provisioner HomeAssistantProxy --not-after=5m --key /tmp/provisioner.key --ca-url https://ca.mafro.internal --root /root/ca.crt)

	mkdir -p /etc/ssl/step

	# retrieve certificate
	step ca certificate "$PROJECT_ID" /etc/ssl/step/client.crt /etc/ssl/step/client.key --token "${TOKEN}" --ca-url https://ca.mafro.internal --force
fi

exec "$@"
