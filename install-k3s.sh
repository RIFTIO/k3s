#!/bin/bash

# K3s Installation Script with Dependencies
# This script installs K3s, Helm, and all required dependencies

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

print_info "Starting K3s installation..."

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    print_error "Cannot detect OS"
    exit 1
fi

print_info "Detected OS: $OS $VERSION"

#check DNS
if ! host www.google.com; then
    print_error "DNS appears to be misconfigured....attempting fix"
    device=$(ip r s  | awk '/default via/ { print $5 }')
    resolvectl dns $device 8.8.8.8
    echo "DNS=8.8.8.8" >>/etc/systemd/resolved.conf
fi
if ! host www.google.com; then
    print_error "DNS appears to be misconfigured. Please repair and re-run this script"
    exit 1
fi

# Update system packages
print_info "Updating system packages...$OS"
case $OS in
    ubuntu|debian)
        apt-get update
        apt-get install -y curl nano wget git tar apt-transport-https ca-certificates gnupg lsb-release
        ;;
    centos|rhel|rocky|almalinux)
        yum update -y
        yum install -y curl nano wget git tar ca-certificates
        ;;
    fedora)
        dnf update -y
        dnf install -y curl nano wget git tar ca-certificates
        ;;
    *)
        print_warning "Unsupported OS. Attempting to continue..."
        ;;
esac

# Check and configure firewall
print_info "Checking firewall configuration..."
if command -v ufw > /dev/null; then
    print_info "Configuring UFW firewall..."
    ufw allow 6443/tcp  # K3s API
    ufw allow 443/tcp   # HTTPS
    ufw allow 80/tcp    # HTTP
    ufw allow 10250/tcp # Kubelet metrics
elif command -v firewall-cmd > /dev/null; then
    print_info "Configuring firewalld..."
    firewall-cmd --permanent --add-port=6443/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=10250/tcp
    firewall-cmd --reload
fi

# Disable swap (required for Kubernetes)
print_info "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load required kernel modules
print_info "Loading kernel modules..."
cat <<EOF > /etc/modules-load.d/k3s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl parameters
print_info "Configuring sysctl parameters..."
cat <<EOF > /etc/sysctl.d/k3s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Create K3s directory
mkdir -p /etc/rancher/k3s

# Install K3s
print_info "Installing K3s..."
curl -sFL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --disable-traefik

# Wait for K3s to be ready
print_info "Waiting for K3s to be ready..."
sleep 10

# Check K3s status
if systemctl is-active --quiet k3s; then
    print_info "K3s service is running"
else
    print_error "K3s service failed to start"
    systemctl status k3s
    exit 1
fi

# Set up kubeconfig for root user
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for node to be ready
print_info "Waiting for node to be ready..."
for i in {1..30}; do
    if /usr/local/bin/k3s kubectl get nodes | grep -q "Ready"; then
        print_info "Node is ready!"
        break
    fi
    sleep 5
done

# Display cluster info
print_info "K3s installation complete!"
echo ""
print_info "Cluster Information:"
/usr/local/bin/k3s kubectl get nodes
echo ""
print_info "K3s version:"
/usr/local/bin/k3s --version
echo ""
print_info "Kubeconfig location: /etc/rancher/k3s/k3s.yaml"
print_info "K3s token location: /var/lib/rancher/k3s/server/node-token"
echo ""
print_info "To use kubectl, run: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
print_info "Or use: k3s kubectl <command>"

# Optional: Create kubectl alias
if ! grep -q "alias kubectl='k3s kubectl'" ~/.bashrc; then
    echo "alias kubectl='k3s kubectl'" >> ~/.bashrc
    print_info "Added kubectl alias to ~/.bashrc"
fi

# Install Helm
print_info "Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify Helm installation
if command -v helm > /dev/null; then
    print_info "Helm installed successfully!"
    helm version
else
    print_error "Helm installation failed"
    exit 1
fi

# Initialize Helm (add stable repo)
print_info "Adding Helm stable repository..."
helm repo add stable https://charts.helm.sh/stable 2>/dev/null || true
helm repo update

echo ""
print_info "Helm Information:"
helm version --short

echo ""
install -d -o ubuntu -g ubuntu /home/ubuntu/.kube
install -o ubuntu -g ubuntu -m 600 /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/kubeconfig
install -o ubuntu -g ubuntu -m 600 /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
echo "export KUBECONFIG=/home/ubuntu/.kube/config" >>/home/ubuntu/.bashrc

cat <<EOF >/etc/security/limits.d/zhone.conf
* soft nofile 16384
* hard nofile 32768
root soft nofile 16384
root hard nofile 32768
EOF

cat <<EOF >/etc/sysctl.d/zhone.conf
sysctl fs.inotify.max_user_instances=4096
sysctl user.max_inotify_instances=4096
EOF

print_info "Installation complete! Reboot is required for all changes to take effect."
