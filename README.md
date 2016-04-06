# README #

This Docker image is used for SAML authentication.

# OpenShift Instructions #
Secrets cannot have key names with 'underscore' present so we rename some of the files.

Create the secret for the httpd saml configuration files (saml-sp.cert, saml-sp.key, saml-sp.xml, sp-idp-metadata.xml) 
```sh
oc secrets new httpd-saml-config-secret ./httpd-saml-config
```

Create the secret for the httpd OSE certificates (authproxy.pem, ca.crt)
```sh
oc secrets new httpd-ose-certs-secret ./httpd-ose-certs
```

Create the secret for the httpd server certificates (server.crt, server.key)
```sh
oc secrets new httpd-server-certs-secret ./httpd-server-certs
```

Create the secret for the httpd client CA cert
```sh
oc secrets new httpd-custom-ca-cert-secret ./ca.crt
```


Perform docker build
```sh
docker build --tag=saml-auth .
```

Add saml-auth template to OSE - (required parameters: APPLICATION_DOMAIN, OSE_API_PUBLIC_URL)
```sh
oc create -f ./saml-auth.template -n openshift
```


Create a new instance (test with '-o json', remove when satisfied with the result)
```sh
oc new-app saml-auth \
    -p APPLICATION_DOMAIN=saml.example.com,OSE_API_PUBLIC_URL=https://ose.example.com:8443 -o json
```


Add secret for SAML config (saml_sp.cert,saml_sp.key,saml_sp.xml,sp-idp-metadata.xml)
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-saml-config --mount-path=/etc/httpd/conf/saml \
     --type=secret --secret-name=httpd-saml-config-secret
```

Add secret for OSE certs (authproxy.pem,ca.crt)
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-ose-certs --mount-path=/etc/httpd/conf/ose_certs \
     --type=secret --secret-name=httpd-ose-certs-secret
```

Add secret for server certs (server.crt,server.key)
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-server-certs --mount-path=/etc/httpd/conf/server_certs \
     --type=secret --secret-name=httpd-server-certs-secret
```

Add secret for custom CA certificate (custom_ca.crt) - optional, duplicate for additional CA certs
```sh
oc volume deploymentconfigs/saml-auth \
     --add --overwrite --name=httpd-custom-ca-cert --mount-path=/etc/pki/ca-trust/source/anchors/custom_ca.crt \
     --type=secret --secret-name=httpd-custom-ca-cert-secret
```



