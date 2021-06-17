# NGINX as an mTLS proxy

## What is this

When running Home Assistant behind an mTLS reverse-proxy, Google Assistant cannot authenticate to
do the oAuth handshake, or post smart home API requests.

The docker config in this directory runs nginx as a reverse-proxy to allow access to Home Assistant
on specific endpoints, [automatically retrieving the TLS client certificates](./docker-entrypoint.sh#L32)
on each request.

Although this public gateway diminishes the security of using TLS client certs in the first place,
a couple of additional controls are in place - forwarding only a specific set of URLs (like an API
gateway) and doing a [double reverse-DNS lookup](https://support.google.com/webmasters/answer/80553) 
to ensure the source of the requests are Google servers.


## How does it work

Double reverse-DNS lookups as a filter in NGINX requires a [custom plugin](https://github.com/flant/nginx-http-rdns).

The multistage docker build in [`Dockerfile.nginx`](./Dockerfile.nginx) first builds the plugin
from source, and then copies it into a standard nginx image. Add the smallstep CLI for retrieving
the mTLS cert from the CA, and the `docker-entrypoint.sh` which the code for retrieving a cert and
writing it to disk before `nginx` starts. Also include the gcloud tools for metadata queries and
secrets retrieval.

Note that `root_ca.crt` is the CA certificate for my personal Smallstep CA.

This design suits Cloud Run well, as the docker container is started fresh on (almost) every invocation.
Because of this, no cert-refresh sidecar is necessary, ala [certbot](https://github.com/certbot/certbot)
since the fresh certs are created (almost) every invocation.


## Infrastructure

See [cloudrun.tf](../infra/cloudrun.tf), which contains the terraform code to setup Cloud Run.


## References

### Running Nginx on Cloud Run

 * https://cloud.google.com/community/tutorials/deploy-react-nginx-cloud-run
 * https://stackoverflow.com/questions/56318026/nginx-container-fails-to-start-on-cloud-run
 * https://docs.nginx.com/nginx/admin-guide/security-controls/securing-http-traffic-upstream

### Verify Google requests with rDNS in Nginx

 * https://support.google.com/webmasters/answer/80553
 * https://github.com/flant/nginx-http-rdns/issues/10
 * https://www.nginx.com/blog/compiling-dynamic-modules-nginx-plus/
 * https://gist.github.com/hermanbanken/96f0ff298c162a522ddbba44cad31081

### Expose real source IP in Cloud Run

 * https://stackoverflow.com/a/60404805/425050

### Reverse Proxy to server requiring SNI (like Caddy)

Some horrific SSL handshake errors led me to a single missing `nginx` directive -- `proxy_ssl_server_name`.
Apparenly [`Caddy`](https://github.com/caddyserver/caddy) requires this to be on.

 * https://stackoverflow.com/a/25330027/425050
