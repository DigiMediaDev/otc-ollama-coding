# --- 1. REGISTER SSH KEY PAIR ---
resource "opentelekomcloud_compute_keypair_v2" "ai_key" {
  name       = "ai-ssh-key"
  public_key = file("${path.module}/ai-ssh-key.pub")
}

# --- 2. IMAGE LOOKUP ---
data "opentelekomcloud_images_image_v2" "gpu_image" {
  name        = "Standard_Ubuntu_22.04_GPU_NV_latest"
  most_recent = true
}

# --- 3. GPU SERVER ---
resource "opentelekomcloud_compute_instance_v2" "ai_server" {
  name              = "gpu-ollama-node"
  flavor_id         = "p2s.2xlarge.8"
  availability_zone = var.availability_zone
  key_pair          = opentelekomcloud_compute_keypair_v2.ai_key.name
  security_groups   = [opentelekomcloud_networking_secgroup_v2.ai_secgroup.name]

  block_device {
    uuid                  = data.opentelekomcloud_images_image_v2.gpu_image.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 100
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = opentelekomcloud_vpc_subnet_v1.ai_subnet.id
  }

  user_data = <<-EOF
#!/bin/bash
exec > /var/log/ki-setup.log 2>&1
export HOME=/root

OBS_BUCKET="ollama-models-eu-de"
OBS_ENDPOINT="https://obs.eu-de.otc.t-systems.com"
MOUNT=/usr/share/ollama/.ollama/models

# 1. Allow SSH TCP forwarding
mkdir -p /etc/ssh/sshd_config.d
echo "AllowTcpForwarding yes" > /etc/ssh/sshd_config.d/99-allow-port-forwarding.conf
systemctl restart ssh

# 2. Install Ollama + AWS CLI
curl -fsSL https://ollama.com/install.sh | sh
apt-get install -y awscli

# 3. Configure AWS CLI for OBS (S3-compatible)
aws configure set aws_access_key_id "${var.obs_ak}"
aws configure set aws_secret_access_key "${var.obs_sk}"
aws configure set default.region eu-de

# 4. Configure Ollama service
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<CONF
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_KEEP_ALIVE=2h"
CONF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# 5. Wait for Ollama API to respond
echo "Waiting for Ollama API..."
until curl -sf http://localhost:11434/ > /dev/null 2>&1; do
  sleep 5
done

# 6. Load models: OBS → Ollama.com
mkdir -p "$MOUNT"
chown -R ollama:ollama /usr/share/ollama/.ollama/

for MODEL in qwen2.5-coder:32b qwen2.5-coder:14b; do
  MODEL_TAG=$(echo "$MODEL" | tr ':' '/')
  OBS_MANIFEST="s3://$OBS_BUCKET/models/manifests/registry.ollama.ai/library/$MODEL_TAG"

  if aws s3 ls "$OBS_MANIFEST" --endpoint-url "$OBS_ENDPOINT" > /dev/null 2>&1; then
    echo "$MODEL found in OBS – loading from OBS (internal, fast)..."
    aws s3 sync "s3://$OBS_BUCKET/models/" "$MOUNT/" --endpoint-url "$OBS_ENDPOINT"
    chown -R ollama:ollama "$MOUNT"
    echo "$MODEL loaded from OBS."

  else
    echo "$MODEL not in OBS – downloading from Ollama.com..."
    sudo -u ollama HOME=/usr/share/ollama /usr/local/bin/ollama pull "$MODEL"
    echo "Syncing $MODEL to OBS for future starts..."
    aws s3 sync "$MOUNT/" "s3://$OBS_BUCKET/models/" --endpoint-url "$OBS_ENDPOINT"
    echo "$MODEL done and backed up to OBS."
  fi
done
EOF
}

# --- 4. ASSOCIATE FLOATING IP WITH SERVER ---
resource "opentelekomcloud_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = opentelekomcloud_vpc_eip_v1.ai_eip.publicip[0].ip_address
  instance_id = opentelekomcloud_compute_instance_v2.ai_server.id
}

# --- 5. OUTPUT ---
output "gpu_server_ip" {
  value = opentelekomcloud_vpc_eip_v1.ai_eip.publicip[0].ip_address
}
