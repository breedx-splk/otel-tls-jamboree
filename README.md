# OTel TLS Jamboree

Exploring java agent and collector TLS configurations.

### Prerequesites

* This guide assumes the use of MacOS. Some commands and tools/urls will change
on other operating systems.
* You must have some standard tools installed (typically through homebrew). Make
  sure you have curl, sed, wget, tar, tee.

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
6. For curiousity, you can see what ciphers are available for TLS and FIPS:
```
$ bin/openssl ciphers -provider fips -v 'kRSA+FIPS:!TLSv1.3'
```

## Key generation

To have the collector listen with TLS, we need to generate a FIPS compliant certificate:
```
$ bin/openssl req -provider fips \
  -x509 -nodes -days 365 -newkey rsa:2048 \
  -subj "/C=US/ST=Oregon/L=Portland/O=Splunk/OU=e/CN=localhost" \
  -addext 'subjectAltName=DNS:localhost' \
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

## JDK setup

We are going to use the Amazon Coretto distribution of the JDK:

```
$ wget https://corretto.aws/downloads/latest/amazon-corretto-17-x64-macos-jdk.tar.gz
$ tar -xvzf amazon-corretto-17-x64-macos-jdk.tar.gz
```

And now we need to add the collector's cert we generated (above) to the 
java trust store:

```
amazon-corretto-17.jdk/Contents/Home/bin/keytool -import \
  -alias collectorTLS \
  -keystore amazon-corretto-17.jdk/Contents/Home/lib/security/cacerts \
  -file collector.crt
```

You will be prompted for the keystore password, which is the default: **changeit**. Literally type `changeit`.

You will be shown some details about the cert and then asked if you should trust it. Enter `yes`.

### Configure BouncyCastle

[BouncyCastle](https://www.bouncycastle.org/download/bouncy-castle-java/) provides a FIPS agreeable 
crypto extension (JCE) for the JDK. We've included the most recent version in the lib dir
of this repo. This will also be passed in the classpath to our test application.

We first need to remove/disable the existing security providers that come with the Coretto JDK 
(even though we think they are probably fine, we explicitly want to use BouncyCastle here).

```
$ sed -i '' 's/^security\.provider\./#security.provider/'  amazon-corretto-17.jdk/Contents/Home/conf/security/java.security
```

And now we need to configure the BouncyCastle provider:

```
$ cat << EOF >> amazon-corretto-17.jdk/Contents/Home/conf/security/java.security
security.provider.1=org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider
security.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:BCFIPS
security.provider.3=sun.security.provider.Sun
EOF
```


## Runing the test

You will need two terminals: one to run the collector and one to run the instrumented java application.
First start the collector:

```
./collector.sh
```

and then in the other terminal start the petclinic java application:

```
./petclinic.sh
```

After a few seconds you should see some metrics and traces being logged. 
