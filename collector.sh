#!/bin/bash

export SPLUNK_REALM=us0

if [ -f env.sh ] ; then
    source env.sh
else
    echo "You must provide an env.sh file that contains SPLUNK_ACCESS_TOKEN".
    exit 1
fi

if [ "" == "${SPLUNK_ACCESS_TOKEN}" ] ; then
  echo "You must define SPLUNK_ACCESS_TOKEN env var."
  exit 1
fi

./otelcol_darwin_arm64 --config collector.yaml | \
    tee collector.log
