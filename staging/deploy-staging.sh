#!/bin/bash
#
# Staging Environment Deployment Script
# This script deploys all components to the Staging VM
#
# Prerequisites:
# - Staging VM is provisioned and accessible
# - kubectl is configured to connect to Staging cluster
# - Helm is installed
#

set -e  # Exit on error

echo "========================================"
echo "  CaringNote Staging Deployment"
echo "========================================"
echo ""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    print_error "kubectl is not configured properly"
    exit 1
fi

print_info "Connected to Kubernetes cluster"
kubectl cluster-info

echo ""
print_warn "This script will deploy to the STAGING environment"
print_warn "Cluster: $(kubectl config current-context)"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deployment cancelled"
    exit 0
fi

echo ""
print_info "Step 1/7: Creating PersistentVolume and PersistentVolumeClaim"
kubectl apply -f ../pvc/postgresql-pv-staging.yaml

echo ""
print_info "Step 2/7: Creating Kubernetes Secrets"
print_warn "Please ensure secrets are created manually or via GitHub Actions workflow"
print_warn "Required secrets in caring-note-staging namespace:"
echo "  - postgresql"
echo "  - keycloak"
echo "  - keycloak-externaldb"
echo "  - api-secret"
echo "  - kcr-secret"
echo ""
read -p "Secrets are ready? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Please create secrets first. See docs/SECURITY.md"
    exit 1
fi

echo ""
print_info "Step 3/7: Installing PostgreSQL (Helm)"
helm upgrade --install postgresql ../common/postgresql \
    -f ../common/postgresql/values.yaml \
    --set auth.database=caring_note_staging \
    --set auth.username=caringnote \
    --set auth.existingSecret=postgresql \
    --set primary.persistence.size=100Gi \
    --set primary.resources.limits.memory=2Gi \
    --set primary.resources.limits.cpu=1000m \
    --set primary.resources.requests.memory=512Mi \
    --set primary.resources.requests.cpu=250m \
    --namespace caring-note-staging \
    --wait \
    --timeout 10m

print_info "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n caring-note-staging --timeout=300s

echo ""
print_info "Step 4/7: Creating Keycloak databases"

# Get PostgreSQL password from Secret
export PGPASSWORD=$(kubectl get secret postgresql -n caring-note-staging -o jsonpath="{.data.postgres-password}" | base64 -d)

# Get Keycloak DB password from Secret
KEYCLOAK_DB_PASSWORD=$(kubectl get secret keycloak-externaldb -n caring-note-staging -o jsonpath="{.data.db-password}" | base64 -d)

print_info "Creating keycloak_staging database..."
kubectl exec -i postgresql-0 -n caring-note-staging -- env PGPASSWORD="$PGPASSWORD" psql -U postgres -c "CREATE DATABASE keycloak_staging;" || true
kubectl exec -i postgresql-0 -n caring-note-staging -- env PGPASSWORD="$PGPASSWORD" psql -U postgres -c "CREATE USER keycloak_staging WITH PASSWORD '$KEYCLOAK_DB_PASSWORD';" || true
kubectl exec -i postgresql-0 -n caring-note-staging -- env PGPASSWORD="$PGPASSWORD" psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE keycloak_staging TO keycloak_staging;" || true

unset PGPASSWORD

echo ""
print_info "Step 5/7: Installing Keycloak (Helm)"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install keycloak bitnami/keycloak \
    -f ../common/keycloak-values.yaml \
    --set auth.existingSecret=keycloak \
    --set auth.passwordSecretKey=admin-password \
    --set httpRelativePath=/keycloak/ \
    --set ingress.enabled=true \
    --set ingress.hostname=stage.caringnote.co.kr \
    --set ingress.extraTls[0].hosts[0]=stage.caringnote.co.kr \
    --set ingress.extraTls[0].secretName=caringnote-tls \
    --set ingress.annotations."nginx\.ingress\.kubernetes\.io/cors-allow-origin"=https://stage.caringnote.co.kr \
    --set adminIngress.enabled=true \
    --set adminIngress.hostname=stage.caringnote.co.kr \
    --set adminIngress.extraTls[0].hosts[0]=stage.caringnote.co.kr \
    --set adminIngress.extraTls[0].secretName=caringnote-tls \
    --set externalDatabase.host=postgresql.caring-note-staging.svc.cluster.local \
    --set externalDatabase.user=postgres \
    --set externalDatabase.database=keycloak_staging \
    --set externalDatabase.existingSecret=keycloak-externaldb \
    --set externalDatabase.existingSecretPasswordKey=db-password \
    --set resources.limits.memory=1536Mi \
    --set resources.limits.cpu=1000m \
    --set resources.requests.memory=512Mi \
    --set resources.requests.cpu=300m \
    --namespace caring-note-staging \
    --wait \
    --timeout 10m

print_info "Waiting for Keycloak to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n caring-note-staging --timeout=600s

echo ""
print_info "Step 6/7: Deploying API and Web applications"
kubectl apply -f api.yaml
kubectl apply -f web.yaml

echo ""
print_info "Step 7/7: Configuring Ingress"
kubectl apply -f ingress.yaml

echo ""
print_info "Waiting for deployments to be ready..."
kubectl rollout status deployment/caring-note-api -n caring-note-staging --timeout=300s
kubectl rollout status deployment/caring-note-web -n caring-note-staging --timeout=300s

echo ""
print_info "========================================"
print_info "  Deployment Completed Successfully!"
print_info "========================================"
echo ""
print_info "Staging URL: https://stage.caringnote.co.kr"
echo ""
print_info "Check deployment status:"
echo "  kubectl get pods -n caring-note-staging"
echo "  kubectl get svc -n caring-note-staging"
echo "  kubectl get ingress -n caring-note-staging"
echo ""
print_info "View logs:"
echo "  kubectl logs -f deployment/caring-note-api -n caring-note-staging"
echo "  kubectl logs -f deployment/caring-note-web -n caring-note-staging"
echo ""
print_warn "Don't forget to:"
echo "  1. Update DNS record: stage.caringnote.co.kr -> Staging VM IP"
echo "  2. Wait for SSL certificate issuance (check: kubectl get certificate)"
echo "  3. Test the application"
echo ""
