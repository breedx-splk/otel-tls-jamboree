#!/bin/bash

export OTEL_RESOURCE_ATTRIBUTES=deployment.environment=tls-jamboree

export JAVA_HOME=$(pwd)/amazon-corretto-17.jdk/Contents/Home
for f in lib/bc*.jar ; do
  if [ "$CP" != "" ] ; then
    CP="${CP}:"
  fi
  CP=${CP}$f
done
CP=lib/spring-petclinic-rest-3.2.1.jar:${CP}
export CP
echo $CP

${JAVA_HOME}/bin/java \
  -cp "${CP}" \
  -Xmx512m -javaagent:./lib/splunk-otel-javaagent-2.6.0.jar \
  -Dorg.bouncycastle.fips.approved_only=true \
  -Dotel.exporter.otlp.endpoint=https://localhost:4318 \
  -Dotel.javaagent.debug=true \
  -Dotel.service.name=spring-petclinic-rest \
  -Dloader.main=org.springframework.samples.petclinic.PetClinicApplication \
  org.springframework.boot.loader.launch.JarLauncher 2>&1 | tee petclinic.log
