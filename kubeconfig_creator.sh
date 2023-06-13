#!/bin/bash

usage() { echo "Usage: $0 -u <username> -g <groupname> [-n <namespace>]" 1>&2; exit 1; }

while getopts u:g:n: flag
do
    case "${flag}" in
        u) K8S_USER=${OPTARG};;
        g) K8S_GROUP=${OPTARG};;
        n) K8S_NAMESPACE=${OPTARG};;
    esac
done

if [ -z "${K8S_USER}" ]; then
    usage
fi

if [ -z "${K8S_NAMESPACE}" ]; then
    NAMESPACE=default
fi

# Create an Alphanumeric User Group Combo
if [ -z "${K8S_GROUP}" ]; then
    COMBO=$(echo -n $K8S_USER | sed 's/[^a-zA-Z0-9]//g')
else
    COMBO=$(echo -n $K8S_USER | sed 's/[^a-zA-Z0-9]//g')-$(echo -n $K8S_GROUP | sed 's/[^a-zA-Z0-9]//g')
fi


# Colour escape codes
CYAN='\033[1;34m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m'

echo -e "⚙️${CYAN} Stage 1 - User - Configuring user keys and certificate signing requests${NC}\n";
echo -e "✨ ${GREEN}Creating key for user ${COMBO} as ${COMBO}.key - ${CYAN}openssl genrsa -out ${COMBO}.key 4096${NC}"
openssl genrsa -out ${COMBO}.key 4096 >/dev/null 2>&1

if [ -z "${K8S_GROUP}" ]; then
    echo -e "✨ ${GREEN}Creating certificate signing request, configuration file for ${COMBO} as ${COMBO}.cnf, ${CYAN}embedding CN=${K8S_USER}${NC}"
else
    echo -e "✨ ${GREEN}Creating certificate signing request, configuration file for ${COMBO} as ${COMBO}.cnf, ${CYAN}embedding CN=${K8S_USER} and O=${K8S_GROUP}${NC}"
fi

cat <<EOF > ${COMBO}.cnf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${K8S_USER}
EOF
if [ ! -z "${K8S_GROUP}" ]; then
    echo "O = ${K8S_GROUP}" >> ${COMBO}.cnf
fi

cat <<EOF >> ${COMBO}.cnf

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
EOF
if [ ! -z "${K8S_GROUP}" ]; then
    cat <<EOF >> ${COMBO}-csr.yaml
  groups:
  - ${K8S_GROUP}
EOF
fi
cat <<EOF >> ${COMBO}-csr.yaml
  request: $(cat ./${COMBO}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF

echo -e "\n⚙️${CYAN} Stage 2 - Kubernetes - Applying Certificate Signing Requests${NC}\n";
echo -e "✨ ${GREEN}Applying kubernetes yaml declaration - ${CYAN}kubectl apply -f ${COMBO}-csr.yaml${NC}"
kubectl apply -f ${COMBO}-csr.yaml >/dev/null 2>&1
echo -e "✨ ${GREEN}Approving kubernetes csr request - ${CYAN}kubectl certificate approve mycsr${NC}"
kubectl certificate approve mycsr >/dev/null 2>&1

echo -e "\n⚙️${CYAN} Stage 3 - Information Capture - Capturing information from Kubernetes${NC}\n";
echo -e "✨ ${GREEN}Capturing variable CLUSTER_NAME - ${CYAN}kubectl config view --minify -o jsonpath={.current-context}${NC}"
export CLUSTER_NAME=$(kubectl config view --minify -o jsonpath={.current-context})
echo -e "✨ ${GREEN}Capturing variable CLIENT_CERTIFICATE_DATA - ${CYAN}kubectl get csr mycsr -o jsonpath='{.status.certificate}'${NC}"
export CLIENT_CERTIFICATE_DATA=$(kubectl get csr mycsr -o jsonpath='{.status.certificate}')
echo -e "✨ ${GREEN}Capturing variable CLIENT_KEY_DATA - ${CYAN}cat ${COMBO}.key | base64 | tr -d '\\\n'${NC}"
export CLIENT_KEY_DATA=$(cat ${COMBO}.key | base64 | tr -d '\n')
echo -e "✨ ${GREEN}Capturing variable CLUSTER_CA - ${CYAN}kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == \"'$(kubectl config current-context)'\") | .cluster.\"certificate-authority-data\"'${NC}"
export CLUSTER_CA=$(kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'$(kubectl config current-context)'") | .cluster."certificate-authority-data"')
echo -e "✨ ${GREEN}Capturing variable CLUSTER_ENDPOINT - ${CYAN}kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == \"'$(kubectl config current-context)'\") | .cluster.\"server\"'${NC}"
export CLUSTER_ENDPOINT=$(kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'$(kubectl config current-context)'") | .cluster."server"')

echo -e "\n⚙️${CYAN} Stage 4 - Kubeconfig - Creating a Kubeconfig file with captured information${NC}\n";
echo -e "✨ ${GREEN}Creating Kubeconfig as ${COMBO}.config - ${YELLOW}Test with - ${CYAN}KUBECONFIG=./${COMBO}.config kubectl${NC}"
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

echo -e "\n⚙️${CYAN} Stage 5 - Cleanup - Moving temporary files from current directory, cleanup Kubernetes CSR${NC}\n";
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
