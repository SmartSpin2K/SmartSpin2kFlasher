# Windows TLS roots

`cacert.pem` is Mozilla's public CA bundle, converted by the curl project:
https://curl.se/docs/caextract.html

Source: https://curl.se/ca/cacert.pem
Mozilla data date: 2026-10-20
Downloaded: 2026-11-04
SHA-256: `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`

The bundle supplements Windows' installed roots for firmware HTTPS requests.
Dart cannot trigger Windows' on-demand root downloads; see
https://github.com/dart-lang/sdk/issues/52266. Certificate chain, hostname, and
expiry verification remain enabled. The app does not change Windows' stores.

Refresh this bundle before releases from the HTTPS source above and compare its
SHA-256 with https://curl.se/ca/cacert.pem.sha256. Update the date and checksum
here when refreshing. Do not replace it with certificates from a failing server.

The CA data is licensed under MPL 2.0; see `LICENSE-MPL-2.0.txt`.
