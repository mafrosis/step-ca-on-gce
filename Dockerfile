FROM google/cloud-sdk:alpine

ENV PORT 8080
ENV STEPPATH /root/.step
ENV STEPFORCEHTTP 1

#RUN curl -o /tmp/step.tgz -L https://github.com/smallstep/certificates/releases/download/v0.14.6/step-certificates_linux_0.14.6_amd64.tar.gz && \
#	tar xzf /tmp/step.tgz --strip-components=1 && \
#	mv bin/step-ca /usr/local/bin

COPY certificates/bin/step-ca /usr/local/bin/step-ca

RUN mkdir -p /root/.step/config && mkdir /root/.step/certs

COPY .step/config/ca.json /root/.step/config
COPY intermediate_ca.crt root_ca.crt /root/.step/certs/
COPY .step/templates /root/.step/templates

# HACK this must be replaced with Secrets Manager
#COPY step-ca-5f96c8-005dd1fe9d26.json /root/gcp.json

CMD ["step-ca", "/root/.step/config/ca.json"]
