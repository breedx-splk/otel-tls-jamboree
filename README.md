# OTel TLS Jamboree

Exploring java agent and collector TLS configurations

## Collector setup

We're using the Splunk distribution of the OpenTelemetry collector for this test, 
version 0.106.1.

First we download the binary and make it runnable:
```
wget https://github.com/signalfx/splunk-otel-collector/releases/download/v0.106.1/otelcol_darwin_arm64
chmod 755 otelcol_darwin_arm64
```

