PROJECT_ID?=step-ca-a48ea0


.PHONY: build
build:
	docker build -f Dockerfile.nginx -t asia.gcr.io/$(PROJECT_ID)/home-assistant-proxy .

.PHONY: build-and-push
build-and-push: build
	docker push asia.gcr.io/$(PROJECT_ID)/home-assistant-proxy

.PHONY: run-test-proxy
run-test-proxy:
	docker run --rm -it -p 8080:8080 -it \
		-e PROJECT_ID=$(PROJECT_ID) \
		-e INSTANCE=egg \
		-e IP=127.0.0.1 \
		-e DEBUG=true \
		-e GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa.json \
		-v $(CURDIR)/docker-entrypoint.sh:/docker-entrypoint.sh:ro \
		-v $(CURDIR)/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
		-v $(CURDIR)/ssl:/etc/ssl/step \
		-v $(CURDIR)/sa.json:/tmp/sa.json:ro \
		asia.gcr.io/step-ca-a48ea0/home-assistant-proxy

.PHONY: test
test:
	@echo "Test success URLs (403 == test passed)"
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/authorize
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/authorize?redirect=egg
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/token
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/providers
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/login_flow
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/login_flow/abcdef
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/frontend_latest/authorize.abcd.js
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/frontend_latest/authorize.1234.js
	@echo "Test failure URLs (404 == test passed)"
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/hax0r
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/authoriz
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/auth/authorized
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/frontend_latest/authorize.1234
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/frontend_latest/authoriz.1234.js
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/frontend_latest/authorize.1234
	curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/frontend_latest/chunk.1234.js
