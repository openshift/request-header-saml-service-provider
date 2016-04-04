FROM rhel7
MAINTAINER Wayne Dovey <wdovey@redhat.com>

LABEL Vendor="RedHat"

RUN yum -y install httpd mod_ssl mod_auth_mellon
ADD saml_sp.cert /etc/httpd/conf/saml_sp.cert
ADD saml_sp.key /etc/httpd/conf/saml_sp.key
ADD saml_sp.xml /etc/httpd/conf/saml_sp.xml
ADD sp-idp-metadata.xml /etc/httpd/conf/sp-idp-metadata.xml
ADD openshift.conf /etc/httpd/conf.d/openshift.conf

ADD httpd.conf /etc/httpd/conf/httpd.conf
RUN rm -fr /etc/httpd/conf.d/welcome.conf
ADD ssl.conf /etc/httpd/conf.d/ssl.conf

ADD localhost.crt /etc/pki/tls/certs/localhost.crt
ADD localhost.key /etc/pki/tls/private/localhost.key
ADD ca.crt /etc/pki/CA/certs/ca.crt
ADD authproxy.pem /etc/pki/tls/certs/authproxy.pem

ADD logged_out.html /var/www/html/logged_out.html

EXPOSE 443

ADD run-httpd.sh /run-httpd.sh
RUN chmod -v +x /run-httpd.sh

CMD ["/run-httpd.sh"]
