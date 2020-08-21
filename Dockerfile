FROM golang:alpine AS builder

ARG GCSFUSE_VERSION=0.30.0

RUN apk --update --no-cache add git fuse fuse-dev
RUN go get -d github.com/googlecloudplatform/gcsfuse
RUN go install github.com/googlecloudplatform/gcsfuse/tools/build_gcsfuse
RUN build_gcsfuse ${GOPATH}/src/github.com/googlecloudplatform/gcsfuse /tmp ${GCSFUSE_VERSION}


FROM google/cloud-sdk:alpine

RUN apk --update --no-cache add fuse

COPY --from=builder /tmp/bin/gcsfuse /usr/bin

ENV STEPPATH /root/.step

RUN curl -o /tmp/step.tgz -L https://github.com/smallstep/certificates/releases/download/v0.14.6/step-certificates_linux_0.14.6_amd64.tar.gz && \
	tar xzf /tmp/step.tgz --strip-components=1 -C /tmp && \
	mv /tmp/bin/step-ca /usr/local/bin && \
	rm -rf /tmp/bin

RUN mkdir -p /root/.step/config && mkdir /root/.step/certs
COPY .step/templates /root/.step/templates

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["step-ca", "/root/.step/config/ca.json"]
