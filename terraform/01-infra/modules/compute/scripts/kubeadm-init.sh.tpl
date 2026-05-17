#!/bin/bash
# Bootstrap skripte za Kubernetes single-node cluster (kubeadm)
# Terraform templatefile varijable: kubernetes_version, pod_cidr, node_name
set -euo pipefail

LOG=/var/log/kubeadm-init.log
exec > >(tee -a $LOG) 2>&1

echo "======================================================"
echo "MLOps Platform Bootstrap — START: $(date)"
echo "======================================================"

# --- Terraform-injected vrijednosti ---
K8S_VERSION="${kubernetes_version}"
POD_CIDR="${pod_cidr}"
NODE_NAME="${node_name}"

# --- System prep ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget git vim htop jq unzip \
  apt-transport-https ca-certificates gnupg lsb-release \
  software-properties-common nfs-common open-iscsi \
  bash-completion

# Isključi swap (Kubernetes zahtjev)
swapoff -a
sed -i '/\bswap\b/d' /etc/fstab

# Postavi hostname
hostnamectl set-hostname $NODE_NAME
echo "127.0.0.1 $NODE_NAME" >> /etc/hosts

# Kernel moduli za containerd
cat > /etc/modules-load.d/containerd.conf << 'MODULES'
overlay
br_netfilter
MODULES
modprobe overlay
modprobe br_netfilter

# Sysctl za Kubernetes networking
cat > /etc/sysctl.d/99-kubernetes.conf << 'SYSCTL'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL
sysctl --system

# --- Containerd ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y containerd.io

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Systemd cgroup driver — obavezno za Kubernetes 1.22+
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
echo "containerd instaliran i konfigurisan."

# --- Kubernetes komponente ---
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
echo "Kubernetes $K8S_VERSION instaliran."

# --- Helm ---
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
  | HELM_INSTALL_DIR=/usr/local/bin bash
echo "Helm instaliran."

# --- kubectl auto-complete ---
kubectl completion bash > /etc/bash_completion.d/kubectl
echo 'alias k=kubectl' >> /home/ubuntu/.bashrc
echo 'complete -o default -F __start_kubectl k' >> /home/ubuntu/.bashrc

# --- Kubeadm init ---
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Private IP: $PRIVATE_IP | Public IP: $PUBLIC_IP"

cat > /tmp/kubeadm-config.yaml << KUBEADM
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $PRIVATE_IP
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  name: $NODE_NAME
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  certSANs:
    - $PUBLIC_IP
    - $PRIVATE_IP
    - localhost
    - 127.0.0.1
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
networking:
  podSubnet: $POD_CIDR
  serviceSubnet: 10.96.0.0/12
etcd:
  local:
    dataDir: /var/lib/etcd
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
KUBEADM

kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs \
  2>&1 | tee /var/log/kubeadm-init-output.log
echo "kubeadm init završen."

# --- Kubeconfig ---
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# Root kubeconfig
export KUBECONFIG=/etc/kubernetes/admin.conf
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /root/.bashrc

# --- Flannel CNI ---
kubectl apply -f \
  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
echo "Flannel CNI instaliran."

# --- Single-node: ukloni control-plane taint ---
# Bez ovoga nikakvi workload podovi ne mogu biti scheduled na master nodu
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
echo "Control-plane taint uklonjen (single-node mode)."

# --- local-path-provisioner — default StorageClass za PV ---
kubectl apply -f \
  https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
echo "local-path StorageClass postavljeno kao default."

# --- Pripremi EBS data disk ---
DATA_DEV=/dev/xvdf
if [ -b $DATA_DEV ]; then
  if ! blkid $DATA_DEV; then
    mkfs.ext4 -F $DATA_DEV
  fi
  mkdir -p /data
  echo "$DATA_DEV /data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount -a
  mkdir -p /data/local-path-provisioner
  chmod 777 /data/local-path-provisioner
  echo "EBS data disk montiran na /data"

  # Rekonfigurisi local-path-provisioner da koristi /data
  kubectl patch configmap local-path-config -n local-path-storage \
    --type=merge \
    -p '{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/data/local-path-provisioner\"]}]}"}}'
fi

# --- Sačuvaj join komandu ---
kubeadm token create --print-join-command > /home/ubuntu/worker-join-command.sh
chmod 600 /home/ubuntu/worker-join-command.sh
chown ubuntu:ubuntu /home/ubuntu/worker-join-command.sh

# --- Čekaj da svi core podovi budu Running ---
echo "Čekam da core podovi budu Running..."
for i in $(seq 1 30); do
  PENDING=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded \
    --no-headers 2>/dev/null | grep -v Terminating | wc -l)
  if [ "$PENDING" -eq 0 ]; then
    echo "Svi core podovi su Running!"
    break
  fi
  echo "  Attempt $i/30 — $PENDING podova još nije Running..."
  sleep 20
done

touch /tmp/kubeadm-init-complete
echo "======================================================"
echo "MLOps Platform Bootstrap — ZAVRŠENO: $(date)"
echo "======================================================"
echo ""
echo "Sljedeći korak:"
echo "  ssh ubuntu@$PUBLIC_IP"
echo "  kubectl get nodes"
