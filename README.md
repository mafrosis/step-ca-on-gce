# Smallstep CA on GCE

## Problem Statement

I run [Home Assistant](https://www.home-assistant.io) in my home network, and wanted to expose that
to the internet in order to integrate with a Google Home smart speaker. A sensible choice is to
require mTLS client authentication on all inbound conections, but that is hard without
[sound PKI](https://smallstep.com/blog/everything-pki/).

This is where the [Smallstep CA](https://github.com/smallstep/certificates) comes in.

```
┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 
  step-ca project                                                        │
│                                                                         
           ┌────────────────────┐                                        │
│          │ Cloud Run          │                                         
           │    ┌───────────┐   │                                        │
│          │    │           │   │              ┌──────────────────────┐   
        ┌──┼───▶│   NGINX   │───┼──────┐       │ VPC subnet           │  │
│       │  │    │           │   │      │       │                      │   
        │  │    └───────────┘   │      │       │  ┌────────────────┐  │  │
│       │  │          │         │    request   │  │                │  │   
        │  └──────────┼─────────┘    TLS cert  │  │  Smallstep CA  │  │  │
│       │             │                └───────┼─▶│    (GCE VM)    │  │   
        │          proxied                     │  │                │  │  │
│       │          request                     │  └────────────────┘  │   
        │         with added                   │                      │  │
│       │            mTLS                      └──────────────────────┘   
        │             │                                                  │
└ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 
        │             │                                                   
      HTTPS           │       ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                       
        │             │         Home network       │                      
        │             │       │                                           
┌─ ── ── ── ── ─┐     │            ┌───────────┐   │                      
│   External          │       │    │   Home    │                          
 Service without│     └───────────▶│ Assistant │   │                      
│    CA cert    │             │    │           │                          
└ ── ── ── ── ──                   └───────────┘   │                      
                              │                                           
                               ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘                      
```

In this diagram, the "external service" cannot talk to Home Assistant as it doesn't support mTLS
connections. 

The solution is to run a reverse-proxy which adds the mTLS certificate and forwards the request
onto Home Assistant. Cloud Run is used as that cheaply provides a HTTPS endpoint on the web to which
the external service can connect.


## Basic Setup

Refer to [Smallstep's instructions](https://smallstep.com/docs/step-ca/installation) along with the
below, as the following will not be up-to-date forever.


### Install Smallstep CLI

The [CLI](https://github/smallstep/cli) is required to setup and interact with the CA from the shell:

    curl -o /tmp/step.tgz -L https://github.com/smallstep/cli/releases/download/v0.15.14/step_linux_0.15.14_amd64.tar.gz
    tar xzf /tmp/step.tgz --strip-components=1 -C /tmp
    mv /tmp/bin/step /usr/local/bin

### Install Smallstep CA

Install the actual [CA](https://github/smallstep/certificates):

    curl -o /tmp/step-ca.tgz -L https://github.com/smallstep/certificates/releases/download/v0.15.11/step-certificates_linux_0.15.11_amd64.tar.gz
    tar xzf /tmp/step-ca.tgz --strip-components=1 -C /tmp
    mv /tmp/bin/step-ca /usr/local/bin


### Configure and run Step CA

Example `step-ca` configuration, adding a JWT provisioner called `admin`, and SSH cert support. This
is copy-pasteable and will create files in `/tmp/step` for you to poke around:

```
> export STEPPATH=/tmp/step && mkdir -p $STEPPATH
> step ca init --name="mafro.dev CA" --provisioner=admin --dns=certs.mafro.dev --address=':443' --ssh
✔ What do you want your password to be? [leave empty and we'll generate one]:
✔ Password: ...

Generating root certificate...
all done!

Generating intermediate certificate...

Generating user and host SSH certificate signing keys...
all done!

✔ Root certificate: /tmp/step/certs/root_ca.crt
✔ Root private key: /tmp/step/secrets/root_ca_key
✔ Root fingerprint: c7641ce4f91993dc3f00000000000000000000000f829c626d20fa02d89600e0
✔ Intermediate certificate: /tmp/step/certs/intermediate_ca.crt
✔ Intermediate private key: /tmp/step/secrets/intermediate_ca_key
✔ SSH user root certificate: /tmp/step/certs/ssh_user_ca_key.pub
✔ SSH user root private key: /tmp/step/secrets/ssh_user_ca_key
✔ SSH host root certificate: /tmp/step/certs/ssh_host_ca_key.pub
✔ SSH host root private key: /tmp/step/secrets/ssh_host_ca_key
✔ Database folder: /tmp/step/db
✔ Templates folder: /tmp/step/templates
✔ Default configuration: /tmp/step/config/defaults.json
✔ Certificate Authority configuration: /tmp/step/config/ca.json
```


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


SSO for SSH
-----------

This section is essentially short-form instructions derived from
[smallstep.com/blog/diy-single-sign-on-for-ssh](https://smallstep.com/blog/diy-single-sign-on-for-ssh/).

Smallstep CA can issue certs for use with SSH. By configuring Google oAuth as the identity provider,
Google does the authentication for us, and `step-ca` issues the cert.


```
┌──────────┐            ┌──────────┐           ┌─ ── ── ── ── ─┐
│          │            │          │                            
│  Client  │────SSH────▶│  Server  │           │    Google     │
│          │            │          │           │   oAuth app   │
└──────────┘            └──────────┘                            
      │                                        └─ ── ── ── ── ─┘
      │                                                ▲        
      │                 ┌──────────┐                   │        
    request             │          │                   │        
      cert─────────────▶│    CA    │────authenticate───┘        
                        │          │                            
                        └──────────┘                            
```

### Setup the Google oAuth app

Note: The naming convention here is to SSH from the _client_ into the _host_ server.

 1. Configure oAuth consent at https://console.developers.google.com/apis/credentials/consent
 2. Create an oAuth app at https://console.developers.google.com/apis/credentials/oauthclient, choosing `Desktop app`

### Create trust relationship between host server and our CA

Next our CA needs to trust an identity document provided by the host system. In the blog post,
the host is an AWS EC2 instance which provides its instance identity to the CA server, and is trusted
via the Amazon signature of the AWS account ID (see [script here](https://gist.github.com/tashian/fde43668cbf6e3227fb13ef51db650b8)).

On the host server, install the [Smallstep CLI tools](#install-smallstep-cli). Next, bootstrap the
`step` client as usual:

```
> FINGERPRINT=$(step certificate fingerprint root_ca.crt)
> step ca bootstrap --ca-url https://ringil --fingerprint $FINGERPRINT
The root certificate has been saved in $HOME/.step/certs/root_ca.crt.
Your configuration has been saved in $HOME/.step/config/defaults.json.
```

Generate a certificate and configure `sshd` to use it. Run the following as root, so it's possible
to write `/etc/ssh`.

In the following example, the host server is named `locke`. The steps are:

1. Generate a token with the `admin` provisioner
2. Inspect the token for your amusement

```
> TOKEN=$(step ca token $(hostname) --ssh --host --provisioner admin)
✔ Provisioner: admin (JWK) [kid: ydABxIT07b0000000000000000000000nGYFRfEGmNA]
✔ Please enter the password to decrypt the provisioner key:
> echo $TOKEN | step crypto jwt inspect --insecure
{
  "header": {
    "alg": "ES256",
    "kid": "ydABxIT07bl-G9jSxfCB45pxNylrKitsnGYFRfEGmNA",
    "typ": "JWT"
  },
  "payload": {
    "aud": "https://ringil:8443/1.0/ssh/sign",
    "exp": 1618046362,
    "iat": 1618046062,
    "iss": "admin",
    "jti": "776b2fce13c90b675f0a1f55712eee80f2504f5f6d4723e0a4fd80e5d35fde40",
    "nbf": 1618046062,
    "sha": "b07c800d7bf36422bd7da01fc2db11efebaafdd5b83092ff82136e75a6d033f9",
    "step": {
      "ssh": {
        "certType": "host",
        "keyID": "locke",
        "principals": [],
        "validAfter": "",
        "validBefore": ""
      }
    },
    "sub": "locke"
  },
  "signature": "E-b6SIaN9atMMo-ICdnoUCjQWMLYuJxkVuB5dBDGjxtzKpPyC-ydnLH5qYV9TTss7MgA2tciMNi9ka-PJ0LNqg"
}
> step ssh certificate $(hostname) /etc/ssh/ssh_host_ecdsa_key.pub --host --sign --provisioner admin --principal $(hostname) --token $TOKEN
✔ CA: https://ringil:8443
✔ Would you like to overwrite /etc/ssh/ssh_host_ecdsa_key-cert.pub [y/n]: y
✔ Certificate: /etc/ssh/ssh_host_ecdsa_key-cert.pub
> step ssh config --host --set Certificate=ssh_host_ecdsa_key-cert.pub --set Key=ssh_host_ecdsa_key
✔ /etc/ssh/sshd_config
✔ /etc/ssh/ca.pub
> systemctl restart sshd
```

### Setup the client to use SSH via OIDC

The following steps are run on the _client_ system, which is connecting to the host configured above.

```
> FINGERPRINT=$(step certificate fingerprint root_ca.crt)
> step ca bootstrap --ca-url https://ringil --fingerprint $FINGERPRINT
The root certificate has been saved in /Users/blackm/.step/certs/root_ca.crt.
Your configuration has been saved in /Users/blackm/.step/config/defaults.json.
> step ssh config
✔ /Users/mafro/.ssh/config
✔ /Users/mafro/.step/ssh/config
✔ /Users/mafro/.step/ssh/known_hosts
```

Configure your SSH client config such that step is used to generate the SSH certificate on demand:

```
> cat ~/.ssh/config
Host locke
    User pi
    UserKnownHostsFile /Users/blackm/.step/ssh/known_hosts
    ProxyCommand step ssh proxycommand %r %h %p --provisioner Google
```

The `Google` provisioner is the OIDC one created at the beginning.

Now, using this configuration is as simple as `ssh locke`, and the OIDC flow is triggered:

```
> ssh locke
✔ Provisioner: Google (OIDC) [client: 824164598483-frmggjqidnm16kjob9ud8a6a6ahvub1v.apps.googleusercontent.com]
Your default web browser has been opened to visit:

https://accounts.google.com/o/oauth2/v2/auth?<snip>

✔ CA: https://ringil:8443
Linux locke 5.10.17-v7l+ #1414 SMP Fri Apr 30 13:20:47 BST 2021 armv7l

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Last login: Thu Jun 17 06:07:51 2021 from 192.168.1.139
pi@locke:~ >
```

If you wanted to have a peek at your SSH certificate, as provisioned by your CA:

```
> step ssh list --raw | step ssh inspect
-:
    Type: ecdsa-sha2-nistp256-cert-v01@openssh.com user certificate
    Public key: ECDSA-CERT SHA256:1p9Ux0LVclOe3wFH9ISo+eUiqoAi/CoK7bE/VSdf2r0
    Signing CA: ECDSA SHA256:WoobT5Uoi8cddLhcxILd5eLoPiq27iEaVCDV/oL/B6I
    Key ID: "m@mafro.net"
    Serial: 8826815887645788865
    Valid: from 2021-06-17T05:44:17 to 2021-06-17T21:44:17
    Principals:
        m
        m@mafro.net
        mafro
        pi
    Critical Options: (none)
    Extensions:
        permit-agent-forwarding
        permit-port-forwarding
        permit-pty
        permit-user-rc
        permit-X11-forwarding
```


### References for oAuth

- https://smallstep.com/blog/diy-single-sign-on-for-ssh/
- https://github.com/smallstep/certificates/blob/master/docs/provisioners.md#oidc


Service-specific JWK Provisioner
--------------------------------

To auto-provision certificates in a service (such as Cloud Run), we can create a unique `JWK`
provisioner dedicated to just that service. An unencrypted private key will need to be made available
on the service - secured in this case in Google KMS.

### Setup a JWK Provisioner

This step only needs to be done once, on the host running the CA.

Generate a new keypair and decrypt the keypair's password for securing in KMS, then create the `JWK`
provisioner from that keypair:

```
> step crypto jwk create proxy-jwk.pub proxy-jwk.key
Please enter the password to encrypt the private JWK:
Your public key has been saved in proxy-jwk.pub.
Your private key has been saved in proxy-jwk.key.
> step crypto jwe decrypt < proxy-jwk.key > proxy-jwk.unencrypted
Please enter the password to decrypt the content encryption key:
> step ca provisioner add HomeAssistantProxy proxy-jwk.key --type JWK
Please enter the password to decrypt proxy-jwk.key:
Please enter the password to encrypt the private JWK:
Success! Your `step-ca` config has been updated. To pick up the new configuration SIGHUP (kill -1 <pid>) or restart the step-ca process.
```

The `.unencrypted` file should be stored securely in your application (in this case GCP KMS), and
then deleted.

### Generate a cert using the JWK provisioner

Use this unencrypted private key to generate your own token, and then certificate, without human
interaction:

```
> TOKEN=$(step ca token token-subject --provisioner HomeAssistantProxy --key proxy-jwk.unencrypted)
✔ Provisioner: HomeAssistantProxy (JWK) [kid: nCdmAqcD-LAdEfMW7qCtqqTBO7z50FQdHvKEzAS_EeY]
> step ca certificate proxy-cert /tmp/client.crt /tmp/client.key --token "$TOKEN" --force
✔ CA: https://ringil:8443
✔ Certificate: /tmp/client.crt
✔ Private Key: /tmp/client.key
```

You can see this in action in the [nginx mTLS proxy](./proxy/docker-entrypoint.sh#L39).


## References

https://smallstep.com/blog/step-certificates/#using-certificates-with-tls
https://smallstep.com/blog/diy-single-sign-on-for-ssh/
https://gitter.im/smallstep/community


GCE Doco
--------

Some notes and recipes for useful things you can do in GCE.


### Running a managed docker image on a VM

GCE can be configured to run a docker container on VM startup - which is a neat way to continue to
use docker for development, but target a VM in production.

The `terraform-google-container-vm` module generates the metadata for a VM instance template, users
just need to see how to configure the module by using
[the examples](https://github.com/terraform-google-modules/terraform-google-container-vm/tree/v2.0.0/examples).

```
module vm_container {
  source = "github.com/terraform-google-modules/terraform-google-container-vm?ref=v2.0.0"

  container = {
    image = format("asia.gcr.io/%s/step-ca", data.google_project.project.project_id)
  }
  restart_policy = "Always"
}

resource google_compute_instance_template tpl {
  region   = var.region
  project  = data.google_project.project.project_id

  machine_type = "e2-micro"
  metadata     = {
    gce-container-declaration: module.vm_container.metadata_value
  }
}

```

* https://cloud.google.com/compute/docs/containers/deploying-containers


### Testing a new docker image without a VM restart

One can quite easily test a new docker image by restarting the `konlet` service. Assuming the `latest`
docker image has been updated on the registry:

0. `IMAGE_ID=$(docker ps --format '{{.ID}}' --filter 'ancestor=asia.gcr.io/step-ca-a3dd5f/step-ca')`
1. `docker rm -f $IMAGE_ID`
2. `docker pull asia.gcr.io/step-ca-a3dd5f/step-ca`
3. `sudo systemctl restart konlet-startup`


### Mounting a host volume into the docker image

The `terraform-google-container-vm` module comes with quite a few useful
[examples](https://github.com/terraform-google-modules/terraform-google-container-vm/blob/v2.0.0/examples/simple_instance/main.tf),
but the following recipe is missing:

```
module vm_container {
  source = "github.com/terraform-google-modules/terraform-google-container-vm?ref=v2.0.0"

  container = {
    image = format("asia.gcr.io/%s/step-ca", data.google_project.project.project_id)

    volumeMounts = [
      {
        name      = "db"
        mountPath = "/root/.step/db"
        readOnly  = false
      },
    ]
  }

  volumes = [
    {
      name = "db"
      hostPath = {
        path = "/home/db"
      }
    },
  ]
}
```

* [konlet source which helped to figure this out](https://github.com/GoogleCloudPlatform/konlet/blob/master/gce-containers-startup/volumes/volumes_test.go#L381)


### Quick SSH via IAP

You can use Google's Identity-Aware Proxy to help with managing SSH access to VMs in GCE. Ensure you
have the right port open on the firewall:

```
resource google_compute_firewall iap_ssh {
  project = google_project.project.project_id
  network = google_compute_network.network.self_link
  name    = "allow-ssh-ingress-from-iap"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
```

And then simply use gcloud to connect:

    gcloud compute ssh ca-x  --tunnel-through-iap --zone australia-southeast1-c


### Using toolbox on COS

After logging into a GCE instance in your shell, use the `toolbox` command to fetch and run a
debian-based docker image handy for debugging.

```
mafro@ca-c3d8 ~ $ toolbox
20200603-00: Pulling from google-containers/toolbox
1c6172af85ee: Pull complete
a4b5cec33934: Pull complete
b7417d4f55be: Pull complete
fed60196983f: Pull complete
8e1533dfae69: Pull complete
112bf8e3d384: Pull complete
1df10c12cc15: Pull complete
b33e020bb38a: Pull complete
938e6be48196: Pull complete
Digest: sha256:36e2f6b8aa40328453aed7917860a8dee746c101dfde4464ce173ed402c1ec57
Status: Downloaded newer image for gcr.io/google-containers/toolbox:20200603-00
gcr.io/google-containers/toolbox:20200603-00
0877997d383a6317d60d0ef76af1f5f914e793f4a65b84094bdec09c284e22c3
mafro-gcr.io_google-containers_toolbox-20200603-00
Please do not use --share-system anymore, use $SYSTEMD_NSPAWN_SHARE_instead.
Spawning container mafro-gcr.io_google-containers_toolbox-20200603-00 on /var/lib/toolbox/mafro-gcr.io_google-containers_toolbox-20200603-00.
Press ^] three times within 1s to kill container.
root@ca-c3d8:~#
```

* https://cloud.google.com/container-optimized-os/docs/how-to/toolbox


### Using gsutil on Container-optimised OS

As container-optimised OS does not come with `gcloud` and friends, the easiest solution is to simply
user docker:

    docker run --rm google/cloud-sdk:alpine gsutil --help


### Configuring a startup/shutdown down script via Terraform

A simple metadata key configures a startup/shutdown script:

```
resource google_compute_instance_template tpl {
  region   = var.region
  project  = data.google_project.project.project_id

  machine_type = "e2-micro"
  metadata     = {
    gce-container-declaration: module.vm_container.metadata_value
    shutdown-script: file("preempt.sh")
    startup-script:  file("startup.sh")
  }

...
```

* https://cloud.google.com/compute/docs/startupscript


### Testing a startup/shutdown down script (in COS)

You can test a startup script in Container-optimised OS with the following command. Substitute
`shutdown` to test the shutdown script.

    sudo google_metadata_script_runner --script-type startup --debug

* https://cloud.google.com/compute/docs/startupscript#on_container-optimized_os_ubuntu_and_sles_images


### Mounting a GCS bucket via fuse

The included [`docker-entrypoint.sh`](./docker-entrypoint.sh#L20) shows mounting a GCS bucket before
a docker application starts up.

The build steps to make `gcsfuse` binary available are in the [`Dockerfile`](./Dockerfile#L5).

* https://serverfault.com/a/968639/89669
