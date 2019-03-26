#!/bin/bash

process_ssl_proxy() {
  if [ -d ${HTTPD_APP_ROOT}/httpd-ssl/proxy ]; then
    echo "---> Looking for SSL Proxy certs for httpd..."
    local ssl_proxy_ca="$(ls -A ${HTTPD_APP_ROOT}/httpd-ssl/proxy/ca.crt | head -n 1)"
    local ssl_proxy_cert="$(ls -A ${HTTPD_APP_ROOT}/httpd-ssl/proxy/*.pem | head -n 1)"
    if [ -f "${ssl_proxy_cert}" ] ; then
      echo "---> Setting SSL Proxy cert file for httpd..."
      sed -i -e "s|^SSLProxyMachineCertificateFile .*$|SSLProxyMachineCertificateFile ${ssl_proxy_cert}|" ${HTTPD_MAIN_CONF_D_PATH}/ssl.conf
      if [ -f "${ssl_proxy_ca}" ]; then
        echo "---> Setting SSL Proxy CA file for httpd..."
        sed -i -e "s|^SSLProxyCACertificateFile .*$|SSLProxyCACertificateFile ${ssl_proxy_ca}|" ${HTTPD_MAIN_CONF_D_PATH}/ssl.conf
      else
        echo "---> Removing SSL key file settings for httpd..."
        sed -i '/^SSLProxyCACertificateFile .*/d'  ${HTTPD_MAIN_CONF_D_PATH}/ssl.conf
      fi
    fi
  fi
}

process_ssl_proxy
