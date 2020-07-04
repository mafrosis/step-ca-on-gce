# Smallstep CA in Cloud Run

## Install Smallstep

    curl -L -O https://github.com/smallstep/certificates/releases/download/v0.14.6/step-cli_0.14.6_amd64.deb
    sudo dpkg -i step-cli_0.14.6_amd64.deb

### Install Certificates CLI

    curl -L -O https://github.com/smallstep/certificates/releases/download/v0.14.6/step-certificates_0.14.6_amd64.deb
    sudo dpkg -i step-certificates_0.14.6_amd64.deb

### Configure and run CA

    step ca init --name "mafro.dev CA" \
        --provisioner admin \
        --dns certs.mafro.dev --address ":443" \
        --password-file password.txt \
        --provisioner-password-file password.txt
    
    step-ca ~/.step/config/ca.json


## Setup GCP

There are a few requirements and manual steps required to make this work. Follow each section below
to ensure you get a working result.


### Prerequisites

 * A GCP Project
 * A DNS zone defined on your project
 * A service account for this project for running terraform. Save the key file somewhere safe.
 * Terraform v0.12.x in your `$PATH`

Set your GCP project ID into an environment variable, so it can be easily used in the below commands
and in the `Makefile`:

    export PROJECT_ID=step-ca-a3dd5f


### GCP Project and DNS zone

Set the GCP project ID, and DNS zone in a file named `terraform.auto.tfvars`, in this format:

    project_id = "${PROJECT_ID}"
    dns_zone   = "ca"


### Use Google Cloud KMS to create and host the CA keys

A beta feature in Smallstep allows us to use private keys generated and hosted by Cloud KMS. This
changes the security posture considerably, since there is no raw access to the private keys, only
IAM-managed access to _use_ the keys for encryption/signing.

Based on the [documentation here](https://github.com/smallstep/certificates/blob/master/docs/kms.md),
run the following: 

```
$ step-cloudkms-init -credentials-file=$GOOGLE_APPLICATION_CREDENTIALS \
    -location=australia-southeast1 \
    -project=${PROJECT_ID} \
    -ring=keyring-name \
    -ssh
Creating PKI ...
✔ Root Key: projects/a3dd5f/locations/global/keyRings/keyring-name/cryptoKeys/root/cryptoKeyVersions/1
✔ Root Certificate: root_ca.crt
✔ Intermediate Key: projects/a3dd5f/locations/global/keyRings/keyring-name/cryptoKeys/intermediate/cryptoKeyVersions/1
✔ Intermediate Certificate: intermediate_ca.crt

Creating SSH Keys ...
✔ SSH User Public Key: ssh_user_ca_key.pub
✔ SSH User Private Key: projects/a3dd5f/locations/global/keyRings/keyring-name/cryptoKeys/ssh-user-key/cryptoKeyVersions/1
✔ SSH Host Public Key: ssh_host_ca_key.pub
✔ SSH Host Private Key: projects/a3dd5f/locations/global/keyRings/keyring-name/cryptoKeys/ssh-host-key/cryptoKeyVersions/1
```

Edit `ca.json`, mapping in the Cloud KMS references according to this mapping:

|Config key | KMS reference |
|-|-|
|`key`| Intermediate Key |
|`hostKey`| SSH Host Private Key |
|`userKey`| SSH User Private Key |

**NB:** The GCP project ID is now hardcoded in `ca.json`, so if you delete and recreate your project,
you will need to update the configuration.


### Webmaster privilege for Terraform service account

The [DNS mapping configuration](https://cloud.google.com/run/docs/mapping-custom-domains) for Cloud
Run is not like normal DNS zones and records. The account which creates the mapping must be an
`Owner` of the domain (or subdomain) in [Google's webmaster central](https://www.google.com/webmasters/verification/details).

Add the service account which runs the terraform as an owner of your custom domain, before running
the terraform.


### Push a working docker image

Cloud Run will not start if the docker image is unavailable in GCR. Solve for that ahead of running
terraform with:

    docker build -t asia.gcr.io/${PROJECT_ID}/step-ca .
    docker push asia.gcr.io/${PROJECT_ID}/step-ca


### Run the terraform

Finally, run the terraform:

    cd infra
    make init
    terraform apply


### Cloud Run service account

The terraform code creates a service account specific to Cloud Run in [`infra/cloudrun.tf`](./infra/cloudrun.tf#L17).

This service account has permission to read the KMS keys necessary to start `step-ca`.

A key for this service account needs to be included in the docker image for the time being. See this
line in the [`Dockerfile`](./Dockerfile#L20). This is all chicken-and-egg and rather hacky, because
I expect it will not be needed long term - the container should be able to authenticate to Google's
API automatically.

This final -hack-step means downloading a key for this service account, and building a new docker
image with the key baked in :/
