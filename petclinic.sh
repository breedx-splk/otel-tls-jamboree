#!/bin/bash

export OTEL_RESOURCE_ATTRIBUTES=deployment.environment=tls-jamboree

export JAVA_HOME=$(pwd)/amazon-corretto-17.jdk/Contents/Home

${JAVA_HOME}/bin/java \
  -Xmx512m -javaagent:./lib/splunk-otel-javaagent-2.6.0.jar \
  -Dotel.exporter.otlp.endpoint=https://localhost:4318 \
  -Dotel.javaagent.debug=true \
  -Dotel.service.name=spring-petclinic-rest \
  -jar lib/spring-petclinic-rest-3.2.1.jar 2>&1 | tee petclinic.log
