FROM quay.io/atgreen/simple-nodeport-service-base:latest
#FROM localhost/simple-nodeport-service-base:latest

COPY . /tmp/src
ARG APP_VERSION=APP_VERSION
ENV APP_VERSION=${APP_VERSION}
RUN APP_SYSTEM_NAME=simple-nodeport-service /usr/libexec/s2i/assemble
CMD DEV_BACKEND=slynk APP_SYSTEM_NAME=simple-nodeport-service APP_EVAL="\"(simple-nodeport-service:start-server)\"" /usr/libexec/s2i/run
