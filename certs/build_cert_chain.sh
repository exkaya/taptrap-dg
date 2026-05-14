#!/bin/bash

# Sollte im Ordner ausgefuehrt werden wo man auch die Zertifikate auch haben moechte.

echo "Erstelle Root CA's private key"
openssl genrsa -out rootCA.key 4096

echo "Erstelle Root CA's Konfigurationsdatei (Metadaten, Organisationsinformationen etc.)"
cat > rootCA.cnf <<'EOF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3_ca

[dn]
C = DE
O = Local Development
CN = HSNR TapTrap Local Development Root CA

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

echo "Erstelle Root CA Zertifikat mithilfe des private key und der Konfigurationsdatei"
openssl req -x509 -new -key rootCA.key -sha256 -days 3650 -out rootCA.crt -config rootCA.cnf

# ============================================================================================
# ============================================================================================

# Inhalt laesst sich testen:

# Sollte die Informationen aus der Konfigurationsdatei ausgeben
# openssl x509 -in rootCA.crt -noout -subject -issuer

# Sollte CA:TRUE ausgeben
# openssl x509 -in rootCA.crt -noout -text | grep -A3 "Basic Constraints"

# ============================================================================================
# ============================================================================================

echo "Erstelle Server's private key"
openssl genrsa -out server.key 2048

echo "Erstelle Server's Konfigurationsdatei (Metadaten, Organisationsinformationen etc.)"
cat > server.cnf <<'EOF'
[req]
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
C = DE
O = Local Development
CN = localhost

[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.0.2.2
EOF

echo "Erstelle Certificate Signing Request"
openssl req -new \
  -key server.key \
  -out server.csr \
  -config server.cnf

# ============================================================================================
# ============================================================================================

# Inhalt laesst sich testen:

# Sollte die Informationen aus der Konfigurationsdatei ausgeben
# openssl x509 -in server.csr -noout -subject

# Sollte die DNS:localhost und die angegebenen IP-Adressen ausgeben
# openssl req -in server.csr -noout -text | grep -A3 "Subject Alternative Name"

# ============================================================================================
# ============================================================================================

echo "Signiere Server's Certificate Signing Request mit dem Root CA"
openssl x509 -req \
  -in server.csr \
  -CA rootCA.crt \
  -CAkey rootCA.key \
  -CAcreateserial \
  -out server.crt \
  -days 825 \
  -sha256 \
  -extfile server.cnf \
  -extensions v3_req

# ============================================================================================
# ============================================================================================

# Inhalt laesst sich testen:

# Sollte Subject aus der Root CA ausgeben
# openssl x509 -in server.crt -noout -subject -issuer

# Sollte die DNS:localhost und die IP-Adressen vom Server ausgeben
# openssl x509 -in server.crt -noout -text | grep -A3 "Subject Alternative Name"

# ============================================================================================
# ============================================================================================

# Sollte OK ausgeben, wenn nicht, nicht weiter fortfahren bis man das Problem findet. 
echo "Verifiziere die Zerifizierungskette"
openssl verify -CAfile rootCA.crt server.crt
