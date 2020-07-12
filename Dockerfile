FROM google/cloud-sdk:alpine

ENV STEPPATH /root/.step

RUN curl -o /tmp/step.tgz -L https://github.com/smallstep/certificates/releases/download/v0.14.6/step-certificates_linux_0.14.6_amd64.tar.gz && \
	tar xzf /tmp/step.tgz --strip-components=1 && \
	mv bin/step-ca /usr/local/bin

RUN mkdir -p /root/.step/config && mkdir /root/.step/certs

COPY .step/config/ca.json /root/.step/config
COPY intermediate_ca.crt root_ca.crt /root/.step/certs/
COPY .step/templates /root/.step/templates

CMD ["step-ca", "/root/.step/config/ca.json"]
