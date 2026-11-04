# Local TLS fixture

This self-signed localhost certificate and private key are **test data only**.
They are never shipped as app assets. The test verifies that the server works
when explicitly trusted, then verifies that the firmware client rejects it.

Regenerate before the certificate expires:

```powershell
openssl req -x509 -newkey rsa:2048 -nodes -keyout test/fixtures/tls/localhost-key.pem -out test/fixtures/tls/localhost-cert.pem -days 3650 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
```
