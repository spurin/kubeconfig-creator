#!/bin/bash

# Configure accordingly
USER=bob
GROUP=cluster-viewonly
NAMESPACE=default

# Create an Alphanumeric User Group Combo
COMBO=$(echo -n $USER | sed 's/[^a-zA-Z0-9]//g')-$(echo -n $GROUP | sed 's/[^a-zA-Z0-9]//g')

# Colour escape codes
CYAN='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[1;32m'
NC='\033[0m'

echo -e "✨ ${GREEN}Creating key for user ${COMBO} as ${COMBO}.key - ${CYAN}openssl genrsa -out ${COMBO}.key 4096${NC}"
openssl genrsa -out ${COMBO}.key 4096 >/dev/null 2>&1

echo -e "✨ ${GREEN}Creating certificate signing request, configuration file for ${COMBO} as ${COMBO}.cnf, ${CYAN}embedding CN=${USER} and O=${GROUP}${NC}"
cat <<EOF > ${COMBO}.cnf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${USER}
O = ${GROUP}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
EOF

echo -e "✨ ${GREEN}Creating certificate signing request as ${COMBO}.csr - ${CYAN}openssl req -config ./${COMBO}.cnf -new -key ${COMBO}.key -nodes -out ${COMBO}.csr${NC}"
openssl req -config ./${COMBO}.cnf -new -key ${COMBO}.key -nodes -out ${COMBO}.csr >/dev/null 2>&1

echo -e "✨ ${GREEN}Creating certificate signing request, kubernetes yaml declaration as ${COMBO}-csr.yaml${NC}"
cat <<EOF > ${COMBO}-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: mycsr
spec:
  groups:
  - ${GROUP}
  request: $(cat ./${COMBO}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF

echo -e "✨ ${GREEN}Applying kubernetes yaml declaration - ${CYAN}kubectl apply -f ${COMBO}-csr.yaml${NC}"
kubectl apply -f ${COMBO}-csr.yaml >/dev/null 2>&1
echo -e "✨ ${GREEN}Approving kubernetes csr request - ${CYAN}kubectl certificate approve mycsr${NC}"
kubectl certificate approve mycsr >/dev/null 2>&1

echo -e "✨ ${GREEN}Capturing variable CLUSTER_NAME - ${CYAN}kubectl config view --minify -o jsonpath={.current-context}${NC}"
export CLUSTER_NAME=$(kubectl config view --minify -o jsonpath={.current-context})
echo -e "✨ ${GREEN}Capturing variable CLIENT_CERTIFICATE_DATA - ${CYAN}kubectl get csr mycsr -o jsonpath='{.status.certificate}'${NC}"
export CLIENT_CERTIFICATE_DATA=$(kubectl get csr mycsr -o jsonpath='{.status.certificate}')
echo -e "✨ ${GREEN}Capturing variable CLIENT_KEY_DATA - ${CYAN}cat ${COMBO}.key | base64${NC}"
export CLIENT_KEY_DATA=$(cat ${COMBO}.key | base64)
echo -e "✨ ${GREEN}Capturing variable CLUSTER_CA - ${CYAN}kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == \"'$(kubectl config current-context)'\") | .cluster.\"certificate-authority-data\"'${NC}"
export CLUSTER_CA=$(kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'$(kubectl config current-context)'") | .cluster."certificate-authority-data"')
echo -e "✨ ${GREEN}Capturing variable CLUSTER_ENDPOINT - ${CYAN}kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == \"'$(kubectl config current-context)'\") | .cluster.\"server\"'${NC}"
export CLUSTER_ENDPOINT=$(kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'$(kubectl config current-context)'") | .cluster."server"')

echo -e "✨ ${GREEN}Creating Kubeconfig as ${COMBO}.config - ${RED}Test with - ${CYAN}KUBECONFIG=./${COMBO}.config kubectl${NC}"
cat <<EOF > $COMBO.config
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_ENDPOINT}
  name: ${CLUSTER_NAME}
users:
- name: ${COMBO}
  user:
    client-certificate-data: ${CLIENT_CERTIFICATE_DATA}
    client-key-data: ${CLIENT_KEY_DATA}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${COMBO}
    namespace: ${NAMESPACE}
  name: ${COMBO}-${CLUSTER_NAME}
current-context: ${COMBO}-${CLUSTER_NAME}
EOF

CLEANUPDIR=tmp-${COMBO}-$(date '+%Y%m%d%H%M%S')
echo -e "🗑️  ${GREEN}Creating temporary files store - ${CYAN}mkdir ${CLEANUPDIR}${NC}"
mkdir ${CLEANUPDIR} 2>&1

echo -e "🗑️  ${GREEN}Cleanup ${COMBO}.key - ${CYAN}mv ${COMBO}.key ${CLEANUPDIR}${NC}"
mv ${COMBO}.key ${CLEANUPDIR}

echo -e "🗑️  ${GREEN}Cleanup ${COMBO}.cnf - ${CYAN}mv ${COMBO}.cnf ${CLEANUPDIR}${NC}"
mv ${COMBO}.cnf ${CLEANUPDIR}

echo -e "🗑️  ${GREEN}Cleanup ${COMBO}.csr - ${CYAN}mv ${COMBO}.csr ${CLEANUPDIR}${NC}"
mv ${COMBO}.csr ${CLEANUPDIR}

echo -e "🗑️  ${GREEN}Cleanup ${COMBO}-csr.yaml - ${CYAN}mv ${COMBO}-csr.yaml ${CLEANUPDIR}${NC}"
mv ${COMBO}-csr.yaml ${CLEANUPDIR} 

echo -e "🗑️  ${GREEN}Cleanup csr/mycsr - ${CYAN}kubectl delete csr/mycsr${NC}"
kubectl delete csr/mycsr >/dev/null 2>&1

