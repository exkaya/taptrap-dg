#!/bin/bash

sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  certs/rootCA.crt

# List the found certificate
# security find-certificate -a -c "HSNR TapTrap Local Development Root CA" /Library/Keychains/System.keychain

# Delete the rootCA again from the Keychain
# sudo security delete-certificate -c "HSNR TapTrap Local Development Root CA" /Library/Keychains/System.keychain