access_token=`curl -k -d "client_id=admin-cli" -d "username={{ idp_admin_user }}" --data-urlencode "password={{ idp_admin_password }}" -d "grant_type=password" "{{ idp_url }}/auth/realms/master/protocol/openid-connect/token"| jq -r '.access_token'`
client_json=`curl -k -v \
    -H "Authorization: bearer $access_token" \
    -H "Content-Type: application/json;charset=utf-8" \
    --data "@/opt/saml2/mellon_metadata.xml" \
    {{ idp_url }}/auth/admin/realms/ocp/client-description-converter` > /opt/saml2/mellon_metadata.json
jq -s '.[0] * .[1]' /opt/saml2/mellon_metadata.json /opt/saml2/mappers.json > /opt/saml2/mellon_metadata_mappers.json
/opt/rh-sso-7.3/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user {{ idp_admin_user }} --password {{ idp_admin_password }}
/opt/rh-sso-7.3/bin/kcadm.sh create clients -r {{ ocp_realm }} -f /opt/saml2/mellon_metadata_mappers.json
/opt/rh-sso-7.3/bin/kcadm.sh create users -r {{ ocp_realm }} -s username={{ realm_test_user }} -s enabled=true -o --fields id,username
/opt/rh-sso-7.3/bin/kcadm.sh set-password -r {{ ocp_realm }} --username {{ realm_test_user }} --new-password {{ realm_test_user_password }}
