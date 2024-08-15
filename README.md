# OTel TLS Jamboree

Exploring java agent and collector TLS configurations.

### Prerequesites

* This guide assumes the use of MacOS. Some commands and tools/urls will change
on other operating systems.
* You must have some standard tools installed (typically through homebrew). Make
  sure you have curl, sed, wget, tar.

## openssl

We're going to build a custom OpenSSL with FIPS support. This will allow us to
create compliant certs.

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
4. Enable fips in the openssl config:
 (Note: this is macos sed syntax)
```
$ sed -i '' "s%# .include fipsmodule.cnf%.include $(pwd)/ssl/fipsmodule.cnf%" ssl/openssl.cnf
$ sed -i '' 's/# fips = fips_sect/fips = fips_sect/' ssl/openssl.cnf
$ sed -i '' "s/# activate = 1/activate = 1/" ssl/openssl.cnf
```
5. Verify that the provider is available:
```
$ bin/openssl list --provider-path providers -provider fips -providers
Providers:
  default
    name: OpenSSL Default Provider
    version: 3.3.1
    status: active
  fips
    name: OpenSSL FIPS Provider
    version: 3.3.1
    status: active
```

## Key generation

To have the collector listen with TLS, we need to generate a FIPS compliant certificate:
```
$ bin/openssl req -provider fips \
  -x509 -nodes -days 365 -newkey rsa:2048 \
  -subj "/C=US/ST=Oregon/L=Portland/O=Splunk/OU=e/CN=splunk.com" \
  -keyout ../collector.key \
  -out ../collector.crt 
```

Then go back to the root of the project:

```
cd ..
```

## Collector setup

We're using the Splunk distribution of the OpenTelemetry collector for this test, 
[version 0.106.1](https://github.com/signalfx/splunk-otel-collector/releases/tag/v0.106.1) 
(the latest version as of this writing).

First we download the binary and make it runnable:
```
wget https://github.com/signalfx/splunk-otel-collector/releases/download/v0.106.1/otelcol_darwin_arm64
chmod 755 otelcol_darwin_arm64
```

Go ahead and check the hash to be super duper secure:
```
$ curl -qsL https://github.com/signalfx/splunk-otel-collector/releases/download/v0.106.1/checksums.txt | \
  grep otelcol_darwin_arm64 && \
  shasum -a 256 otelcol_darwin_arm64
```
This should show the same hash twice:
```
c337727a41b976c6547b72738e238a1d8a6150777d065f2b5555f57229fbc74a  otelcol_darwin_arm64
c337727a41b976c6547b72738e238a1d8a6150777d065f2b5555f57229fbc74a  otelcol_darwin_arm64
```

You'll need an ingest token ([docs here](https://docs.splunk.com/observability/en/admin/authentication/authentication-tokens/org-tokens.html)). 
Copy one and paste it into a new file named `env.sh` that looks like this:

```bash
export SPLUNK_ACCESS_TOKEN=<your_token>
```

And then start the collector:

```
./collector.sh
```

## JDK setup

We are going to use the Amazon Coretto distribution of the JDK:

```
$ wget https://corretto.aws/downloads/latest/amazon-corretto-17-x64-macos-jdk.tar.gz
$ tar -xvzf amazon-corretto-17-x64-macos-jdk.tar.gz
```
