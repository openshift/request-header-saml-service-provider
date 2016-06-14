## Assumptions
This document assumes you already have a OpenShift environment with a working
router and registry (the defaults are fine).  Fully operation DNS is not a
requirement for local testing.  The goal of this document is to show how an
OpenShift environment running anywhere can integrate with a locally running
development KeyCloak environment for test purposes.  It is by no means an
exhuastive document on KeyCloak configuration.

The service provider pod in this example is `sp.example.org`.  It will only
need to resolve on the system running the web browser that is testing the
authentication.

## install keycloak

Install a containerized version of keycloak:

```
docker run --name keycloak -e KEYCLOAK_LOGLEVEL=TRACE -p 8080:8080 -p 9990:9990 jboss/keycloak
docker exec keycloak keycloak/bin/add-user-keycloak.sh -u <USERNAME> -p <PASSWORD>
docker restart keycloak
```

Browse to <ip>:8080 and click the link to access the admin console.  Create a
new realm called 'openshift'.  Switch to this realm.

### Creating the Identity Provider
Create a new SAML 2.0 Identity Provider.  Set the `Single Sign-On Service URL`
and `Single Logout Service URL`, .  Be sure to update the hostname of the saml
service provider pod in your environment.

| key | value |
| --- |:------| 
| Single Sign-On Service URL | https://sp.example.org/mellon/postResponse |
| Single Logout Service URL | https://sp.example.org/mellon/logout | 

###Creating the SAML metadata
Now create a new Client in Keycloak matching the name of your service.  On the
Settings page added the following `Valid Redirect URIs`

```
https://sp.example.org/*
https://<your master>:8443/*
```

Edit the `Fine Grain SAML Endpoint Configuration` and add the following:

| key | value |
| --- |:------| 
| Assertion Consumer Service POST Binding URL | https://sp.example.org/mellon/postResponse |
| logout-service-post-binding-url | https://sp.example.org/mellon/logout | 

Click the `Installation` tab and then download the `Mod Auth Mellon files` and
copy the contents to a directory named `httpd-saml-config` on your Master (or
wherever you have an oc client with cluster-admin credentials).

Once there rename the following files:

```
mv sp-metadata.xml saml-sp.xml
mv idp-metadata.xml sp-idp-metadata.xml
mv client-cert.pem saml-sp.cert
mv client-private-key.pem saml-sp.key
```

###Creating a User
Now create a user for authentication in Keycloak.  Make sure to set a password
in the `Credentials` tab.
