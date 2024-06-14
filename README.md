# Overview
Demo Coder

## Installation on Kubernetes with Helm

### 1. Create a namespace for Coder, such as coder
```bash
kubectl create namespace coder
```

### 2. Create a PostgreSQL deployment. Coder does not manage a database server for you

You can install Postgres manually on your cluster using the Bitnami PostgreSQL Helm chart. There are some helpful guides on the internet that explain sensible configurations for this chart. Example:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install coder-db bitnami/postgresql \
    --namespace coder \
    -f values-postgres.yaml
```

The cluster-internal DB URL for the above database is:

`postgres://coder:coder@coder-db-postgresql.coder.svc.cluster.local:5432/coder?sslmode=disable`

Ensure you set up periodic backups so you don't lose data.

### 3. Create a secret with the database URL

```bash
kubectl create secret generic coder-db-url -n coder \
   --from-literal=url="postgres://coder:coder@coder-db-postgresql.coder.svc.cluster.local:5432/coder?sslmode=disable"
```

### 4. Install with Helm

```bash
helm repo add coder-v2 https://helm.coder.com/v2
helm upgrade --install coder coder-v2/coder \
    --namespace coder \
    -f secrets.yaml -f values.yaml
```

### 5. Log in to Coder

I'm using an ingress to expose Coder. You can use a LoadBalancer or NodePort.

### 6. To use the GitHub Oauth Method

Update the `values.yaml` file to include the following:
```yaml
coder:
  env:
    - name: CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS
      value: "true"
    - name: CODER_OAUTH2_GITHUB_CLIENT_ID
      value: "533...des"
    - name: CODER_OAUTH2_GITHUB_CLIENT_SECRET
      value: "G0CSP...7qSM"
    # If setting allowed orgs, comment out CODER_OAUTH2_GITHUB_ALLOW_EVERYONE and its value
    - name: CODER_OAUTH2_GITHUB_ALLOWED_ORGS
      value: "your-org"
    # If allowing everyone, comment out CODER_OAUTH2_GITHUB_ALLOWED_ORGS and it's value
    #- name: CODER_OAUTH2_GITHUB_ALLOW_EVERYONE
    #  value: "true"
```

then upgrade:
```bash
helm repo update
helm upgrade coder coder-v2/coder \
  --namespace coder \
  -f values.yaml
```

## Using Minikube in a Workspace

```bash
minikube start --cpus=3 --memory=6GB
```