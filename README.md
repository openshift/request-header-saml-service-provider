# README #

This Docker image is used for SAML authentication.

# OpenShift Instructions #
Secrets cannot have key names with an 'underscore' in them, so when creating a secret using a directory of files we need to rename the files accordingly.

Create the secret for the httpd saml configuration files (saml-sp.cert, saml-sp.key, saml-sp.xml, sp-idp-metadata.xml) 
```sh
mkdir ./httpd-saml-config
cp saml-sp.cert saml-sp.key saml-sp.xml sp-idp-metadata.xml ./httpd-saml-config/
oc secrets new httpd-saml-config-secret ./httpd-saml-config
```

Create the secret for the httpd OSE certificates (authproxy.pem, ca.crt)
```sh
mkdir ./httpd-ose-certs
cp authproxy.pem ca.crt ./httpd-ose-certs/
oc secrets new httpd-ose-certs-secret ./httpd-ose-certs
```

Create the secret for the httpd server certificates (server.crt, server.key)
```sh
mkdir ./httpd-server-certs
cp server.crt server.key ./httpd-server-certs/
oc secrets new httpd-server-certs-secret ./httpd-server-certs
```

Create the secret for a custom CA cert - optional
```sh
cp /etc/origin/master/ca.crt ./
oc secrets new httpd-custom-ca-cert-secret ./ca.crt
```


Create the docker image
```sh
docker build --tag=saml-auth .
docker tag -f <id> <repo>/saml-auth
docker push <repo>/saml-auth
```

Add saml-auth template to OSE - (required parameters: APPLICATION_DOMAIN, OSE_API_PUBLIC_URL)
```sh
oc create -f ./saml-auth.template -n openshift
```


Create a new application (test with '-o json', remove when satisfied with the result)
```sh
oc new-app saml-auth \
    -p APPLICATION_DOMAIN=saml.example.com,OSE_API_PUBLIC_URL=https://ose.example.com:8443/oauth/authorize -o json
```


Add a secret for the SAML configuration (saml-sp.cert,saml-sp.key,saml-sp.xml,sp-idp-metadata.xml)
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-saml-config --mount-path=/etc/httpd/conf/saml \
     --type=secret --secret-name=httpd-saml-config-secret
```

Add a secret for OSE certs (authproxy.pem,ca.crt)
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-ose-certs --mount-path=/etc/httpd/conf/ose_certs \
     --type=secret --secret-name=httpd-ose-certs-secret
```

Add a secret for server certs (server.crt,server.key)
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-server-certs --mount-path=/etc/httpd/conf/server_certs \
     --type=secret --secret-name=httpd-server-certs-secret
```

Add a secret for a custom CA certificate (custom_ca.crt) - optional, duplicate for additional CA certs
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-custom-ca-cert --mount-path=/etc/pki/ca-trust/source/anchors/custom_ca.crt \
     --type=secret --secret-name=httpd-custom-ca-cert-secret
```

The template defines replicas as 0 so scale up:
```sh
oc scale --replicas=1 dc saml-auth
```

Update /etc/origin/master/master-config.yml:
```
oauthConfig:
  assetPublicURL: https://ose.example.com:8443/console/
  grantConfig:
    method: auto
  identityProviders:
  - name: my_request_header_idp
    challenge: false
    login: true
    mappingMethod: add
    provider:
      apiVersion: v1
      kind: RequestHeaderIdentityProvider
      loginURL: "https://saml.example.com/mod_auth_mellon?${query}"
      clientCA: /etc/origin/master/proxyca.crt
      headers:
      - Remote-User
  masterCA: ca.crt

```
