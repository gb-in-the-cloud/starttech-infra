#!/usr/bin/env bash
# =============================================================================
# deploy-infrastructure.sh
#
# Two-phase deployment script for StartTech infrastructure.
# CloudFront's ALB-Backend origin depends on the ALB created by the AWS
# Load Balancer Controller inside the cluster, which itself depends on the
# cluster existing first — hence the two-phase apply.
#
# Usage:
#   ./scripts/deploy-infrastructure.sh init
#   ./scripts/deploy-infrastructure.sh plan
#   ./scripts/deploy-infrastructure.sh apply-phase1
#   ./scripts/deploy-infrastructure.sh bootstrap-alb
#   ./scripts/deploy-infrastructure.sh apply-phase2
#   ./scripts/deploy-infrastructure.sh destroy
# =============================================================================

set -euo pipefail

# ─── Directories ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"
LOG_FILE="$ROOT_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"

# ─── Config ───────────────────────────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-starttech-eks}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
  exit 1
}

info() {
  echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

step() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
print_banner() {
  local action="$1"
  echo -e "${BLUE}"
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║           StartTech Infrastructure Deployment             ║"
  echo "║           Action : $(printf '%-36s' "$action")║"
  echo "║           Region : $(printf '%-36s' "$AWS_REGION")║"
  echo "║           Cluster: $(printf '%-36s' "$CLUSTER_NAME")║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ─── Preflight Checks ─────────────────────────────────────────────────────────
check_prerequisites() {
  step "Running preflight checks"

  # Terraform
  if ! command -v terraform &>/dev/null; then
    error "Terraform not installed. See https://developer.hashicorp.com/terraform/install"
  fi
  info "Terraform: $(terraform version -json | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])")"

  # AWS CLI
  if ! command -v aws &>/dev/null; then
    error "AWS CLI not installed. See https://aws.amazon.com/cli/"
  fi
  info "AWS CLI:   $(aws --version 2>&1 | cut -d' ' -f1)"

  # AWS credentials
  if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured. Run 'aws configure' first."
  fi
  info "Account:   $(aws sts get-caller-identity --query Account --output text)"
  info "Region:    $(aws configure get region)"

  # kubectl
  if ! command -v kubectl &>/dev/null; then
    warn "kubectl not installed — needed for bootstrap-alb and apply-phase2."
  else
    info "kubectl:   $(kubectl version --client --short 2>/dev/null | head -1)"
  fi

  # Helm
  if ! command -v helm &>/dev/null; then
    warn "Helm not installed — needed for bootstrap-alb."
  else
    info "Helm:      $(helm version --short 2>/dev/null)"
  fi

  log "Preflight checks passed ✓"
}

# ─── tfvars Guard ─────────────────────────────────────────────────────────────
require_tfvars() {
  if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
    warn "terraform.tfvars not found."
    if [[ -f "$TF_DIR/terraform.tfvars.example" ]]; then
      warn "Copying terraform.tfvars.example → terraform.tfvars..."
      cp "$TF_DIR/terraform.tfvars.example" "$TF_DIR/terraform.tfvars"
      error "Edit $TF_DIR/terraform.tfvars with real values then re-run."
    fi
    error "terraform.tfvars.example not found either. Cannot continue."
  fi
}

# ─── Confirm Prompt ───────────────────────────────────────────────────────────
confirm() {
  local message="$1"
  local expected="${2:-yes}"
  echo -e "${YELLOW}"
  echo "  ════════════════════════════════════════════════════"
  echo "  $message"
  echo "  Account : $(aws sts get-caller-identity --query Account --output text)"
  echo "  Region  : $AWS_REGION"
  echo "  ════════════════════════════════════════════════════"
  echo -e "${NC}"
  read -rp "  Type '${expected}' to confirm: " INPUT
  if [[ "$INPUT" != "$expected" ]]; then
    warn "Cancelled by user."
    exit 0
  fi
}

# ─── Print Terraform Outputs ──────────────────────────────────────────────────
print_outputs() {
  step "Terraform Outputs"
  cd "$TF_DIR"
  echo -e "${CYAN}"
  terraform output 2>/dev/null | tee -a "$LOG_FILE"
  echo -e "${NC}"
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_init() {
  print_banner "init"
  check_prerequisites
  step "Initialising Terraform"
  cd "$TF_DIR"

  terraform init -upgrade 2>&1 | tee -a "$LOG_FILE"

  log "Terraform initialised ✓"
  info "Log: $LOG_FILE"
}

cmd_plan() {
  print_banner "plan"
  check_prerequisites
  require_tfvars
  step "Running Terraform Plan"
  cd "$TF_DIR"

  terraform fmt -check -recursive 2>&1 | tee -a "$LOG_FILE" \
    && log "Formatting check passed ✓" \
    || { warn "Formatting issues found. Running terraform fmt..."; terraform fmt -recursive; }

  terraform validate 2>&1 | tee -a "$LOG_FILE"
  log "Validation passed ✓"

  terraform plan \
    -var-file="terraform.tfvars" \
    -out=tfplan \
    2>&1 | tee -a "$LOG_FILE"

  log "Plan complete ✓ — saved to tfplan"
  info "Log: $LOG_FILE"
}

cmd_apply_phase1() {
  print_banner "apply-phase1"
  check_prerequisites
  require_tfvars

  step "Phase 1: VPC · EKS · S3 · ECR · ElastiCache · CloudFront (placeholder ALB)"
  confirm "You are about to apply Phase 1 infrastructure."

  cd "$TF_DIR"

  # Run plan first if no saved plan exists
  if [[ ! -f "$TF_DIR/tfplan" ]]; then
    log "No saved plan found — running terraform plan first..."
    terraform plan \
      -var-file="terraform.tfvars" \
      -out=tfplan \
      2>&1 | tee -a "$LOG_FILE"
  fi

  terraform apply "tfplan" 2>&1 | tee -a "$LOG_FILE"

  log "Phase 1 apply complete ✓"

  step "Configuring kubectl"
  aws eks update-kubeconfig \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    2>&1 | tee -a "$LOG_FILE"

  log "kubectl configured ✓"

  # Verify nodes are ready
  info "Verifying worker nodes..."
  kubectl get nodes 2>&1 | tee -a "$LOG_FILE"

  print_outputs

  echo -e "${YELLOW}"
  echo "  ════════════════════════════════════════════════════"
  echo "  Phase 1 complete. Next steps:"
  echo ""
  echo "  1. Deploy your Kubernetes manifests (Ingress etc.)"
  echo "  2. Run: ./scripts/deploy-infrastructure.sh bootstrap-alb"
  echo "  3. Run: ./scripts/deploy-infrastructure.sh apply-phase2"
  echo "  ════════════════════════════════════════════════════"
  echo -e "${NC}"

  # Cleanup plan file
  rm -f "$TF_DIR/tfplan"
  info "Log: $LOG_FILE"
}

cmd_bootstrap_alb() {
  print_banner "bootstrap-alb"
  check_prerequisites

  step "Installing AWS Load Balancer Controller via Helm"

  # Get VPC ID from Terraform outputs
  cd "$TF_DIR"
  VPC_ID=$(terraform output -raw vpc_id 2>/dev/null) \
    || error "Could not get vpc_id from Terraform outputs. Run apply-phase1 first."

  info "VPC ID: $VPC_ID"
  info "Cluster: $CLUSTER_NAME"
  info "Region: $AWS_REGION"

  # Add EKS Helm repo
  helm repo add eks https://aws.github.io/eks-charts 2>&1 | tee -a "$LOG_FILE"
  helm repo update 2>&1 | tee -a "$LOG_FILE"

  # Install AWS Load Balancer Controller
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set region="$AWS_REGION" \
    --set vpcId="$VPC_ID" \
    --wait \
    2>&1 | tee -a "$LOG_FILE"

  log "AWS Load Balancer Controller installed ✓"

  # Verify controller is running
  step "Verifying Controller"
  kubectl get pods -n kube-system \
    -l app.kubernetes.io/name=aws-load-balancer-controller \
    2>&1 | tee -a "$LOG_FILE"

  echo -e "${YELLOW}"
  echo "  ════════════════════════════════════════════════════"
  echo "  AWS Load Balancer Controller is running."
  echo ""
  echo "  Next steps:"
  echo "  1. Apply your Kubernetes Ingress manifest:"
  echo "     kubectl apply -f k8s/ingress.yaml"
  echo ""
  echo "  2. Watch for the ALB to be provisioned:"
  echo "     kubectl get ingress starttech-backend -w"
  echo ""
  echo "  3. Once ADDRESS is populated, copy the DNS name"
  echo "     and run apply-phase2."
  echo ""
  echo "  To get the ALB DNS name run:"
  echo "     kubectl get ingress starttech-backend \\"
  echo "       -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  echo "  ════════════════════════════════════════════════════"
  echo -e "${NC}"

  info "Log: $LOG_FILE"
}

cmd_apply_phase2() {
  print_banner "apply-phase2"
  check_prerequisites
  require_tfvars

  step "Phase 2: Update CloudFront with real ALB DNS"

  # Try to get ALB DNS automatically from kubectl
  ALB_DNS=""
  if command -v kubectl &>/dev/null; then
    info "Attempting to fetch ALB DNS from kubectl..."
    ALB_DNS=$(kubectl get ingress starttech-backend \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
      2>/dev/null || echo "")
  fi

  # If not found automatically, ask the user
  if [[ -z "$ALB_DNS" ]]; then
    warn "Could not fetch ALB DNS automatically."
    echo -e "${CYAN}"
    echo "  Run this to get the ALB DNS name:"
    echo "  kubectl get ingress starttech-backend \\"
    echo "    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
    echo -e "${NC}"
    read -rp "  Enter the ALB DNS name manually: " ALB_DNS
  else
    log "ALB DNS found automatically: $ALB_DNS"
    read -rp "  Use this ALB DNS? '$ALB_DNS' (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
      read -rp "  Enter the ALB DNS name manually: " ALB_DNS
    fi
  fi

  if [[ -z "$ALB_DNS" ]]; then
    error "ALB DNS name cannot be empty."
  fi

  info "Using ALB DNS: $ALB_DNS"

  confirm "You are about to re-apply CloudFront with the real ALB origin."

  cd "$TF_DIR"

  terraform apply \
    -var-file="terraform.tfvars" \
    -var="alb_dns_name=${ALB_DNS}" \
    -auto-approve \
    2>&1 | tee -a "$LOG_FILE"

  log "Phase 2 apply complete ✓"
  print_outputs

  CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain 2>/dev/null || echo "N/A")

  echo -e "${GREEN}"
  echo "  ════════════════════════════════════════════════════"
  echo "  Deployment complete!"
  echo ""
  echo "  CloudFront : https://$CLOUDFRONT_DOMAIN"
  echo "  ALB Backend: http://$ALB_DNS"
  echo "  ════════════════════════════════════════════════════"
  echo -e "${NC}"

  info "Log: $LOG_FILE"
}

cmd_destroy() {
  print_banner "destroy"
  check_prerequisites
  require_tfvars

  step "Terraform Destroy"
  confirm "⚠  You are about to DESTROY ALL infrastructure. This is irreversible." "destroy"

  cd "$TF_DIR"

  terraform destroy \
    -var-file="terraform.tfvars" \
    -auto-approve \
    2>&1 | tee -a "$LOG_FILE"

  log "Infrastructure destroyed ✓"
  info "Log: $LOG_FILE"
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${CYAN}"
  echo "Usage: $0 <command>"
  echo ""
  echo "Commands:"
  echo "  init          Initialise Terraform providers and modules"
  echo "  plan          Validate and preview infrastructure changes"
  echo "  apply-phase1  Deploy VPC, EKS, S3, ECR, ElastiCache, CloudFront"
  echo "  bootstrap-alb Install AWS Load Balancer Controller via Helm"
  echo "  apply-phase2  Re-apply CloudFront with the real ALB DNS name"
  echo "  destroy       Tear down all infrastructure"
  echo ""
  echo "Typical deployment order:"
  echo "  1. init"
  echo "  2. plan"
  echo "  3. apply-phase1"
  echo "  4. bootstrap-alb"
  echo "  5. apply-phase2"
  echo -e "${NC}"
  exit 1
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  init)          cmd_init ;;
  plan)          cmd_plan ;;
  apply-phase1)  cmd_apply_phase1 ;;
  bootstrap-alb) cmd_bootstrap_alb ;;
  apply-phase2)  cmd_apply_phase2 ;;
  destroy)       cmd_destroy ;;
  *)             usage ;;
esac
