#!/usr/bin/env bash
# =============================================================================
# deploy-infra.sh
# StartTech Infrastructure deployment script
#
# Usage:
#   ./scripts/deploy-infra.sh init
#   ./scripts/deploy-infra.sh plan
#   ./scripts/deploy-infra.sh apply
#   ./scripts/deploy-infra.sh destroy
# =============================================================================

set -euo pipefail

# ─── Directories ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"
LOG_FILE="$ROOT_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"

# ─── Config ───────────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-eu-west-1}"
CLUSTER_NAME="${CLUSTER_NAME:-starttech-cluster}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Logging ──────────────────────────────────────────────────────────────────
log()  { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"; }
error(){ echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info() { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"; }
step() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
print_banner() {
  echo -e "${BLUE}"
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║           StartTech Infrastructure Deployment             ║"
  echo "║           Action : $(printf '%-36s' "$1")║"
  echo "║           Region : $(printf '%-36s' "$AWS_REGION")║"
  echo "║           Cluster: $(printf '%-36s' "$CLUSTER_NAME")║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ─── Preflight Checks ─────────────────────────────────────────────────────────
check_prerequisites() {
  step "Running preflight checks"

  if ! command -v terraform &>/dev/null; then
    error "Terraform not installed. See https://developer.hashicorp.com/terraform/install"
  fi
  info "Terraform: $(terraform version -json | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])")"

  if ! command -v aws &>/dev/null; then
    error "AWS CLI not installed. See https://aws.amazon.com/cli/"
  fi
  info "AWS CLI:   $(aws --version 2>&1 | cut -d' ' -f1)"

  if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured. Run 'aws configure' first."
  fi
  info "Account:   $(aws sts get-caller-identity --query Account --output text)"
  info "Region:    $(aws configure get region)"

  if ! command -v kubectl &>/dev/null; then
    warn "kubectl not installed — needed for post-deploy cluster access."
  else
    info "kubectl:   $(kubectl version --client --short 2>/dev/null | head -1)"
  fi

  log "Preflight checks passed ✓"
}

# ─── tfvars Guard ─────────────────────────────────────────────────────────────
require_tfvars() {
  if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
    if [[ -f "$TF_DIR/terraform.tfvars.example" ]]; then
      warn "terraform.tfvars not found. Copying example..."
      cp "$TF_DIR/terraform.tfvars.example" "$TF_DIR/terraform.tfvars"
      error "Edit $TF_DIR/terraform.tfvars with real values then re-run."
    fi
    error "terraform.tfvars not found. Cannot continue."
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

# ─── Print Outputs ────────────────────────────────────────────────────────────
print_outputs() {
  step "Terraform Outputs"
  cd "$TF_DIR"
  echo -e "${CYAN}"
  terraform output 2>/dev/null | tee -a "$LOG_FILE"
  echo -e "${NC}"
}

# ─── Configure kubectl ────────────────────────────────────────────────────────
configure_kubectl() {
  step "Configuring kubectl"
  cd "$TF_DIR"

  CLUSTER=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "$CLUSTER_NAME")

  aws eks update-kubeconfig \
    --region "$AWS_REGION" \
    --name "$CLUSTER" \
    2>&1 | tee -a "$LOG_FILE"

  log "kubectl configured ✓"

  info "Verifying cluster nodes..."
  kubectl get nodes 2>&1 | tee -a "$LOG_FILE"
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

  log "Plan complete ✓"
  info "Log: $LOG_FILE"
}

cmd_apply() {
  print_banner "apply"
  check_prerequisites
  require_tfvars

  step "Deploying StartTech Infrastructure"
  confirm "You are about to deploy all StartTech infrastructure."

  cd "$TF_DIR"

  if [[ ! -f "$TF_DIR/tfplan" ]]; then
    log "No saved plan found — running plan first..."
    terraform plan \
      -var-file="terraform.tfvars" \
      -out=tfplan \
      2>&1 | tee -a "$LOG_FILE"
  fi

  terraform apply "tfplan" 2>&1 | tee -a "$LOG_FILE"

  log "Infrastructure deployed ✓"

  configure_kubectl
  print_outputs

  rm -f "$TF_DIR/tfplan"

  echo -e "${GREEN}"
  echo "  ════════════════════════════════════════════════════"
  echo "  Deployment complete!"
  echo ""
  echo "  CloudFront : https://$(cd "$TF_DIR" && terraform output -raw cloudfront_domain 2>/dev/null)"
  echo "  EKS        : $(cd "$TF_DIR" && terraform output -raw eks_cluster_name 2>/dev/null)"
  echo "  Redis      : $(cd "$TF_DIR" && terraform output -raw redis_endpoint 2>/dev/null)"
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
  echo "  init     Initialise Terraform providers and modules"
  echo "  plan     Validate and preview infrastructure changes"
  echo "  apply    Deploy all infrastructure to AWS"
  echo "  destroy  Tear down all infrastructure"
  echo ""
  echo "Typical usage:"
  echo "  1. ./scripts/deploy-infra.sh init"
  echo "  2. ./scripts/deploy-infra.sh plan"
  echo "  3. ./scripts/deploy-infra.sh apply"
  echo -e "${NC}"
  exit 1
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  init)    cmd_init ;;
  plan)    cmd_plan ;;
  apply)   cmd_apply ;;
  destroy) cmd_destroy ;;
  *)       usage ;;
esac