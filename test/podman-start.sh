#!/bin/sh

set -x

podman pod stop simple-nodeport-service-pod || true
podman pod rm simple-nodeport-service-pod || true

BASE_HASH=$(sha512sum src/simple-nodeport-service.asd | cut -b 1-8)
podman images | grep ${BASE_HASH} > /dev/null 2>&1 || podman build -f build/Dockerfile.base --no-cache -t simple-nodeport-service-base:${BASE_HASH} .

podman build -f build/Dockerfile -t simple-nodeport-service:latest --no-cache --from simple-nodeport-service-base:${BASE_HASH} src

cat test/test-pod.yml | sed -e 's/\/home\/runner\/work\/simple-nodeport-service\/simple-nodeport-service/./'
cat test/test-pod.yml | sed -e 's/\/home\/runner\/work\/simple-nodeport-service\/simple-nodeport-service/./' | podman play kube -

timeout -s TERM 45 bash -c 'while [[ "$(curl -s -o /dev/null -L -w ''%{http_code}'' http://localhost:8080/health)" != "200" ]]; do echo "Waiting for http://localhost:8080/health" && sleep 2; done' || true

echo ===========================================================================
echo
echo Application: http://localhost:8080
echo
echo Prometheus : http://localhost:9101/metrics
echo
echo Use emacs to \'sly-connect\' to localhost port 4005
echo
echo Run \'make podman-stop\' to stop the test pod
echo
echo ===========================================================================

podman logs -f simple-nodeport-service-pod-simple-nodeport-service
