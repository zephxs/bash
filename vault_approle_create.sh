#!/bin/bash
### Create Approle + Policy + Pass in Hashicorp Vault

# Preset
SECENGINE='secrets'         # Location in the vault where secrets are created
SECENV=''                   # Environment [prod, pprod, anything..]
SECNAME=''                  # Name used to create Secret and Policy
SECPASS=''                  # Password to set

_HELPFUNCTION(){
echo -e "### Create Vault Password with Approle

# Usage:
-n|--name              # Name of the Secret to create
-p|--pass              # Password to set
-e|--env               # Environment of the secret (folder)

# Exemples:
$(basename $0) -n redfront -e pprod -p 'mypass'
$(basename $0) -n redfront -p 'mypass'
"
}

while (( "$#" )); do
  case "$1" in
    -n|--name)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        SECNAME="$2"; shift 2;
      else
        echo "$2 Secret Name is missing.."; exit 1;
      fi
      ;;
    -p|--pass)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        SECPASS="$2"; shift 2;
      else
        echo "$2 Password to set is missing.."; exit 1;
      fi
      ;;
    -e|--env)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        SECENV="$2"; shift 2;
      else
        echo "$2 Environment to set is missing.."; exit 1;
      fi
      ;;
    -h|--help)
      _HELPFUNCTION
      exit
      ;;
    *)
      _HELPFUNCTION
      exit
      ;;
  esac;
done

[ -z $SECENGINE -o -z $SECNAME -o -z $SECPASS ] && { echo "Missing params.. exit"; exit 1; }

# Create secret [Password you need to access in puppet]
echo -e "\n# Create Secret: $SECNAME"
if [ -z $SECENV ]; then
  vault kv put -mount="$SECENGINE" "$SECNAME" password="$SECPASS"
  cat > vault-template.hcl<<EOF
path "/${SECENGINE}/data/${SECNAME}" {
  capabilities = [ "read" ]
}
EOF
else
  vault kv put -mount="$SECENGINE" "${SECENV}/${SECNAME}" password="$SECPASS"
  cat > vault-template.hcl<<EOF
path "/${SECENGINE}/data/${SECENV}/${SECNAME}" {
  capabilities = ["read"]
}
EOF
fi

# Write a Policy for the Secret
echo -e "\n# Write Policy:"
vault policy write "$SECNAME" ./vault-template.hcl

# Create AppRole for the Policy
echo -e "\n# Create Approle:"
vault write auth/approle/role/${SECNAME} \
bind_secret_id=true \
token_policies="$SECNAME"

##### PARAM that can be added if needed
#token_type=batch \
#secret_id_ttl=600m \
#token_ttl=10h \
#token_max_ttl=30h \
#secret_id_num_uses=400 \
#token_policies="$SECNAME" \
#secret_id_bound_cidrs="0.0.0.0/0","127.0.0.1/32" \
#secret_id_ttl=60m \
#secret_id_num_uses=0 \
#enable_local_secret_ids=false \
#token_bound_cidrs="0.0.0.0/0","127.0.0.1/32" \
#token_num_uses=0 \
#token_ttl=1h \
#token_max_ttl=3h \
#token_type=default \
#period="" \

# Get role-id of the Approle
ROLE_ID=$(vault read -field=role_id auth/approle/role/${SECNAME}/role-id)
echo -e "\n# Get AppRole Id: $ROLE_ID"

# Generate secret-id for the Approle
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/${SECNAME}/secret-id)
echo -e "\n# Generate SecretId: $SECRET_ID"

# Allow Approle secret-id login
echo -e "\n# Write login config:"
vault write auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"
echo

# Show puppet config (copy-paste)
echo -e "################\nPuppet Code to Add:"
if [ -z $SECENV ]; then
echo "
  \$vaultsecret = vault_lookup::lookup('secrets/data/${SECNAME}', {
    'vault_addr'  => 'https://vault.corp.com',
    'auth_method' => 'approle',
    'role_id'     => '$ROLE_ID',
    'secret_id'   => '$SECRET_ID',
    'field'       => 'password'
  })
  \$protected_secret = \$vaultsecret.unwrap
"
else
echo "
  \$vaultsecret = vault_lookup::lookup('secrets/data/${SECENV}/${SECNAME}', {
    'vault_addr'  => 'https://vault.corp.com',
    'auth_method' => 'approle',
    'role_id'     => '$ROLE_ID',
    'secret_id'   => '$SECRET_ID',
    'field'       => 'password'
  })
  \$protected_secret = \$vaultsecret.unwrap
"
fi

# Show warnings and recovery commands if secret is lost
echo -e "\n# WARNING: secret-id CANNOT be accessed anymore, please copy it !!!\n# if lost, you can rewrite a new one with:"
echo "vault write -f -field=secret_id auth/approle/role/${SECNAME}/secret-id"
echo "vault write auth/approle/login role_id=\"$ROLE_ID\" secret_id=\"secret created from the last command\""
echo
