# kubeconfig-creator

A convenient wrapper script for creating kubeconfig files based on RBAC groups.

Understanding RBAC in k8s can be difficult ... rather than using ```kubectl auth can-i```, this script creates a quick kubeconfig file with the associated user and group.

## Example workflow -

### Create a readonly cluster role

```
kubectl create clusterrole cluster-viewer --verb=list,get --resource='*'
```

### Bind the cluster role to a group
```
kubectl create clusterrolebinding cluster-view-role-binding --clusterrole=cluster-viewer --group=cluster-viewonly
```

### Execute the script, passing variables as follows
```
-u <user>
-g <group>
[-n <namespace>] - optional, will use default if not specified
```

### Run the script
```
./kubeconfig_creator.sh -u bob -g cluster-viewonly
⚙️ Stage 1 - User - Configuring user keys and certificate signing requests

✨ Creating key for user bob-clusterviewonly as bob-clusterviewonly.key - openssl genrsa -out bob-clusterviewonly.key 4096
✨ Creating certificate signing request, configuration file for bob-clusterviewonly as bob-clusterviewonly.cnf, embedding CN=bob and O=cluster-viewonly
✨ Creating certificate signing request as bob-clusterviewonly.csr - openssl req -config ./bob-clusterviewonly.cnf -new -key bob-clusterviewonly.key -nodes -out bob-clusterviewonly.csr
✨ Creating certificate signing request, kubernetes yaml declaration as bob-clusterviewonly-csr.yaml

⚙️ Stage 2 - Kubernetes - Applying Certificate Signing Requests

✨ Applying kubernetes yaml declaration - kubectl apply -f bob-clusterviewonly-csr.yaml
✨ Approving kubernetes csr request - kubectl certificate approve mycsr

⚙️ Stage 3 - Information Capture - Capturing information from Kubernetes

✨ Capturing variable CLUSTER_NAME - kubectl config view --minify -o jsonpath={.current-context}
✨ Capturing variable CLIENT_CERTIFICATE_DATA - kubectl get csr mycsr -o jsonpath='{.status.certificate}'
✨ Capturing variable CLIENT_KEY_DATA - cat bob-clusterviewonly.key | base64 | tr -d '\n'
✨ Capturing variable CLUSTER_CA - kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'default'") | .cluster."certificate-authority-data"'
✨ Capturing variable CLUSTER_ENDPOINT - kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'default'") | .cluster."server"'

⚙️ Stage 4 - Kubeconfig - Creating a Kubeconfig file with captured information

✨ Creating Kubeconfig as bob-clusterviewonly.config - Test with - KUBECONFIG=./bob-clusterviewonly.config kubectl

⚙️ Stage 5 - Cleanup - Moving temporary files from current directory, cleanup Kubernetes CSR

🗑️  Creating temporary files store - mkdir tmp-bob-clusterviewonly-20230613101447
🗑️  Cleanup bob-clusterviewonly.key - mv bob-clusterviewonly.key tmp-bob-clusterviewonly-20230613101447
🗑️  Cleanup bob-clusterviewonly.cnf - mv bob-clusterviewonly.cnf tmp-bob-clusterviewonly-20230613101447
🗑️  Cleanup bob-clusterviewonly.csr - mv bob-clusterviewonly.csr tmp-bob-clusterviewonly-20230613101447
🗑️  Cleanup bob-clusterviewonly-csr.yaml - mv bob-clusterviewonly-csr.yaml tmp-bob-clusterviewonly-20230613101447
🗑️  Cleanup csr/mycsr - kubectl delete csr/mycsr
```

### Test accordingly, 1st command will work
```
% KUBECONFIG=./bob-clusterviewonly.config kubectl get nodes
NAME             STATUS   ROLES           AGE   VERSION
docker-desktop   Ready    control-plane   72m   v1.24.2
```

### 2nd command will fail (as expected)
```
% KUBECONFIG=./bob-clusterviewonly.config kubectl run nginx --image=nginx
Error from server (Forbidden): pods is forbidden: User "bob" cannot create resource "pods" in API group "" in the namespace "default"
```
