# OTel TLS Jamboree

Exploring java agent and collector TLS configurations.

### Prerequesites

* This guide assumes the use of MacOS. Some commands and tools/urls will change
on other operating systems.
* You must have some standard tools installed (typically through homebrew). Make
  sure you have curl, sed, wget, tar, tee.

## OpenSSL

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
$ sed -i '' 's/^security\.provider\./#security.provider/' \
  amazon-corretto-17.jdk/Contents/Home/conf/security/java.security
```

Now we change the `KeyManagerFactory` to PKIX:
```
$ sed -i '' 's/^ssl.KeyManagerFactory.algorithm=SunX509/ssl.KeyManagerFactory.algorithm=PKIX/' \
  amazon-corretto-17.jdk/Contents/Home/conf/security/java.security
```

And now we need to configure the BouncyCastle provider:

```
$ cat << EOF >> amazon-corretto-17.jdk/Contents/Home/conf/security/java.security
security.provider.1=org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider
security.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:BCFIPS
security.provider.3=sun.security.provider.Sun
security.provider.4=SunJCE
security.provider.5=SunJSSE
security.provider.6=SunEC
security.provider.7=SunRsaSign
EOF
```

Note: We have kept 5 of the Sun-based providers. The agent fails for different reasons without these.

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

If you want to verify the TLS configuration of the running collector, we can 
use openssl for that again:

```
$ ./openssl/bin/openssl s_client -connect localhost:4318
Connecting to 127.0.0.1
CONNECTED(00000005)
Can't use SSL_get_servername
depth=0 C=US, ST=Oregon, L=Portland, O=Splunk, OU=e, CN=localhost
verify error:num=18:self-signed certificate
verify return:1
depth=0 C=US, ST=Oregon, L=Portland, O=Splunk, OU=e, CN=localhost
verify return:1
---
Certificate chain
 0 s:C=US, ST=Oregon, L=Portland, O=Splunk, OU=e, CN=localhost
   i:C=US, ST=Oregon, L=Portland, O=Splunk, OU=e, CN=localhost
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Aug 15 17:15:42 2024 GMT; NotAfter: Aug 15 17:15:42 2025 GMT
---
Server certificate
-----BEGIN CERTIFICATE-----
MIIDuzCCAqOgAwIBAgIUK591cP5LQWdGG9IKowzMwiGELwAwDQYJKoZIhvcNAQEL
BQAwYjELMAkGA1UEBhMCVVMxDzANBgNVBAgMBk9yZWdvbjERMA8GA1UEBwwIUG9y
dGxhbmQxDzANBgNVBAoMBlNwbHVuazEKMAgGA1UECwwBZTESMBAGA1UEAwwJbG9j
YWxob3N0MB4XDTI0MDgxNTE3MTU0MloXDTI1MDgxNTE3MTU0MlowYjELMAkGA1UE
BhMCVVMxDzANBgNVBAgMBk9yZWdvbjERMA8GA1UEBwwIUG9ydGxhbmQxDzANBgNV
BAoMBlNwbHVuazEKMAgGA1UECwwBZTESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjAN
BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAySTAYHyVdNYthNlyegxgwait6iGC
2PFyGzS+Jf4/9iNBFICZdOPYIMyQDGN1OQLHAIVqcNVg/ND/MmBPOSCQqvkbr4Gc
k7arT+1pcq4dV4SnbcfpxRnpAykVjfexbIii9obSQ1DwGeMeBOBfkMdTRhv2t2nV
udrRnsPIeGNdKUqm+klrls5ENr8b2tzVnNtsdz2Fo0StHwaUI+2nsveqYVUirpMj
GGEZoBQCwsrZt3T9gvahbtcMsqNLbxPmIFzwgF9krk7BsCT2hRvcauJW5JGoTHGb
dF+r6WRgtj8n2FJyMRTXQ5364X4K0xWafpHt2+3uuEZyAQ/xdKTEPdQahwIDAQAB
o2kwZzAdBgNVHQ4EFgQUqIkNgLCRzO90zARU4cdFWo+ypkEwHwYDVR0jBBgwFoAU
qIkNgLCRzO90zARU4cdFWo+ypkEwDwYDVR0TAQH/BAUwAwEB/zAUBgNVHREEDTAL
gglsb2NhbGhvc3QwDQYJKoZIhvcNAQELBQADggEBADIz5N90eweFDvz6wHZnJh6/
pcuhCV34q/lzOQefzDYToV6GoBq0vvIcMJ/iSKn/y61d1uaXs2pzA6Tj7VVSJqK0
Keic6MC/62CjQC7RyV5xDZ9/m74g8s4bDD+HMaowZDD0qJqRcFv6TbQnP1L8aIVK
s/m9/iOLCnzVtmmWDpcxNroi4GZL5UpvYlfBvzVBg4uPqzV9t9yGsRcDtmpglME8
T//0YqUOGEU8tKIEuab17ZLlxE+XnG2d7fJBw28DmpBPKWlgJ0bbkaHS4Z9qjia2
ckhGhtbW6fJqskfUFn3j94k8UbT4FWFChmnzdiZZ6vkP7uoDG9w74oNvfLOcBMY=
-----END CERTIFICATE-----
subject=C=US, ST=Oregon, L=Portland, O=Splunk, OU=e, CN=localhost
issuer=C=US, ST=Oregon, L=Portland, O=Splunk, OU=e, CN=localhost
---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 1499 bytes and written 363 bytes
Verification error: self-signed certificate
---
New, TLSv1.3, Cipher is TLS_AES_128_GCM_SHA256
Server public key is 2048 bit
This TLS version forbids renegotiation.
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 18 (self-signed certificate)
---
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_128_GCM_SHA256
    Session-ID: D459FB0735B71D1D7013146C32F972D4E0BF14AA5FE675F973C3C7187B4B1D33
    Session-ID-ctx:
    Resumption PSK: 4FDE0376F9D8D2626D61DA5036799C2FC530F980644E6833464053EDEB82B9CF
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 604800 (seconds)
    TLS session ticket:
    0000 - 01 c0 1f ff 0e 7c e8 f5-41 8d f2 33 fe 5d 09 74   .....|..A..3.].t
    0010 - e0 11 57 df 15 2a c8 cc-3d 67 75 27 22 79 74 df   ..W..*..=gu'"yt.
    0020 - ce a6 c7 23 31 70 65 18-47 b2 03 6e 24 52 b5 25   ...#1pe.G..n$R.%
    0030 - 1b 6f ee 10 ac be e9 b1-de 85 95 9e 6d e2 5c f1   .o..........m.\.
    0040 - ca 5e 8b 0f e6 b8 e5 5c-e8 ab 73 ee cd 37 e3 e0   .^.....\..s..7..
    0050 - 5d b6 f4 42 7c 98 7a c6-19 96 d8 c8 f6 28 8c 32   ]..B|.z......(.2
    0060 - 18 e8 ef 28 b8 e7 27 67-5e                        ...(..'g^

    Start Time: 1723832959
    Timeout   : 7200 (sec)
    Verify return code: 18 (self-signed certificate)
    Extended master secret: no
    Max Early Data: 0
---
read R BLOCK
```
