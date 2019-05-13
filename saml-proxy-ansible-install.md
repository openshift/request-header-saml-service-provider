# SAML Proxy - Ansible Install

Instrutions for installing the SAML Proxy via Ansible.

* [Warning](#warning)
* [Setup](#setup)
* [Install Proxy](#install-proxy)
* [Update Identity Providers](#update-identity-providers)
* [Update Web Console Logout](#update-web-console-logout)
* [Debugging](#debugging)

# Warning

The Ansbile instructions are new and less tested then the manual instructions, use at your own discression.

# Setup

## Create Ansible Inventory

We recommend you setup your inventory based on the example provided and update the username, password, and URL fields as you need.  You may also want to provide an ``ansible.cfg`` file as well.  The ``inventory`` and ``ansible.cfg`` files are currently ignored by git.  

The playbooks should be run from a bastion, or jump, host outside of the cluster itself.

```sh
mv inventory.example inventory
```

| Variable                      | Description
|-------------------------------|------------
| `TODO`                        | TODO

## Login to OpenShift

Login to your OpenShift Client with a cluster-admin user from the system you will be running the playbooks from

```sh
oc login https://openshift.ocp.example.com:443
```

# Install Proxy

This creates an instance of an Apache HTTPD server with mod_auth_mellon installed, based off the current httpd24 image provided by the Red Hat Container Catalog.  If you need to debug your server, you can follow further steps in the `saml-service-provider/debug` folder.

```sh
ansible-playbook playbooks/install-saml-auth.yaml
```

# Update Identity Providers

This configures the OAuth OpenShift Provider to Proxy to your SAML Proxy provider, which in turn proxies to your IdP.  Be sure your RequestHeader fields used here match those in your saml-auth openshift.conf file.

```sh
ansible-playbook playbooks/install-oauth-on-master.yaml
```

# Update Web Console Logout

This is written ONLY for OCP 3.9 and above.  For lower, you need to update the assetConfig entries in the master-config.yaml.

```sh
ansible-playbook playbooks/update-webconsole-cm.yaml
```

# Debugging

See [Debugging](README.md#debugging).
