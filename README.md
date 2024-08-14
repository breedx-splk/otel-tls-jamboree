# OTel TLS Jamboree

Exploring java agent and collector TLS configurations

## Collector setup

We're using the Splunk distribution of the OpenTelemetry collector for this test, 
[version 0.106.1](https://github.com/signalfx/splunk-otel-collector/releases/tag/v0.106.1) 
(the latest version as of this writing).

First we download the binary and make it runnable:
```
wget https://github.com/signalfx/splunk-otel-collector/releases/download/v0.106.1/otelcol_darwin_arm64
chmod 755 otelcol_darwin_arm64
```

You'll need an ingest token ([docs here](https://docs.splunk.com/observability/en/admin/authentication/authentication-tokens/org-tokens.html)). 
Copy one and paste it into a new file named `env.sh` that looks like this:

```bash
export SPLUNK_ACCESS_TOKEN=<your_token>
```

Now you'll need to generate a certificate for the collector.

## openssl

We're going to build openssl with fips support.

1. Download openssl and unpack it:
```
wget https://github.com/openssl/openssl/releases/download/openssl-3.3.1/openssl-3.3.1.tar.gz
tar -xvzf openssl-3.3.1.tar.gz
cd openssl-3.3.1
```
2. Now we build it with fips enabled:
 ```
./Configure --prefix="$(pwd)/../openssl" enable-fips
make install
cd ../openssl
```
3. Verify that the fips config is there:
```
$ cat ssl/fipsmodule.cnf
[fips_sect]
activate = 1
conditional-errors = 1
security-checks = 1
tls1-prf-ems-check = 1
drbg-no-trunc-md = 1
module-mac = <big long mac string>
```

