# otc-ollama-coding

Terraform-based setup to run [Ollama](https://ollama.com) with large coding LLMs on a GPU instance on [Open Telekom Cloud (OTC)](https://open-telekom-cloud.com). Designed for use with [VS Code Continue](https://continue.dev) as a local AI coding assistant.

## What it does

- Provisions a GPU server on OTC with a single command (`./ki-start.sh`)
- Installs Ollama automatically on first boot via cloud-init
- Attaches a **persistent EVS volume** for model storage — models survive server restarts
- Opens an **SSH tunnel** so VS Code Continue can reach Ollama at `http://localhost:11434`
- Tears down only the server on `./ki-stop.sh` — the network, IP and model volume are preserved

## Architecture

```
Your machine                  Open Telekom Cloud (eu-de-01)
─────────────────             ──────────────────────────────────────────
VS Code Continue              ┌─ VPC: 10.0.0.0/16
  │                           │   └─ Subnet: 10.0.1.0/24
  │ http://localhost:11434    │       └─ GPU Server (gpu-ollama-node)
  │                           │           ├─ Ollama :11434 (localhost only)
  └──── SSH Tunnel ───────────┤           └─ EVS Volume /dev/vdb → /models
         Port 22              │               ├─ qwen2.5-coder:32b (~20 GB)
                              │               └─ qwen2.5-coder:14b (~9 GB)
                              └─ Elastic IP (static, always kept)
```

## Project structure

| File | Purpose |
|------|---------|
| `provider.tf` | OTC provider config, credentials via env vars |
| `network.tf` | VPC, subnet, elastic IP (never destroyed) |
| `security.tf` | Security group: SSH (22) + Ollama API (11434) |
| `compute.tf` | GPU server, persistent EVS volume, cloud-init setup script |
| `ki-start.sh` | Start script: terraform apply → wait for Ollama → open SSH tunnel |
| `ki-stop.sh` | Stop script: destroy server + volume attachment, keep network & volume |

### compute.tf in detail

Four resources are defined:

1. **`opentelekomcloud_compute_keypair_v2`** — registers your public SSH key on OTC
2. **`opentelekomcloud_blockstorage_volume_v2`** — 100 GB SSD EVS volume in `eu-de-01`, never destroyed by `ki-stop.sh`
3. **`opentelekomcloud_compute_instance_v2`** — the GPU server with inline `user_data` script that:
   - Enables SSH TCP forwarding
   - Installs Ollama
   - Mounts the EVS volume to `/usr/share/ollama/.ollama/models`
   - Formats the volume only on first use (`blkid` check)
   - Runs `resize2fs` so the full volume size is always available
   - Fixes permissions for the `ollama` system user
   - Waits for the Ollama API to respond before pulling models
   - Pulls `qwen2.5-coder:32b` and `qwen2.5-coder:14b` only if not already on the volume
4. **`opentelekomcloud_compute_volume_attach_v2`** — attaches the EVS volume to the server

### ki-start.sh in detail

```
1. Kill any existing SSH tunnel on port 11434 (waits for port to be released)
2. terraform apply  →  abort on failure
3. Wait for SSH to respond (retry loop)
4. Wait for Ollama API at http://localhost:11434/ (retry loop, max 60 min)
5. Open SSH tunnel: local:11434 → server:localhost:11434
```

### ki-stop.sh in detail

```
1. Kill local SSH tunnel
2. terraform destroy -target volume_attachment
3. terraform destroy -target server
   → EVS volume, elastic IP and network resources are NOT destroyed
```

## First-time setup

### Prerequisites

- Terraform >= 1.0
- SSH key pair — generate once and place in the project root:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/ai-ssh-key.pem -N ""
  cp ~/.ssh/ai-ssh-key.pem.pub ./ai-ssh-key.pub
  ```
- [Continue](https://marketplace.visualstudio.com/items?itemName=Continue.continue) — VS Code extension for AI coding assistance
- OTC credentials exported as environment variables:

```bash
export OS_ACCESS_KEY="your-ak"
export OS_SECRET_KEY="your-sk"
```

### Initialize Terraform

```bash
terraform init
```

### Start

```bash
./ki-start.sh
```

First boot takes **20–40 minutes** (Ollama install + model downloads ~29 GB from internet).
Subsequent starts in the **same AZ** take **~3 minutes** — models are already on the EVS volume.
Starts in a **different AZ** take **~5–10 minutes** — models are copied from OBS (internal OTC network).

### Switch Availability Zone

If the GPU flavor is unavailable in the default AZ, pass the target AZ as argument:

```bash
./ki-start.sh eu-de-02
```

This creates a new EVS volume in `eu-de-02` and loads models from OBS instead of the internet.

### Stop (preserve models and IP)

```bash
./ki-stop.sh
```

## VS Code Continue configuration

`~/.continue/config.yaml`:

```yaml
name: Cloud GPU Config
version: 1.0.0
schema: v1
models:
  - name: Qwen (OTC GPU)
    provider: ollama
    model: qwen2.5-coder:32b
    apiBase: "http://127.0.0.1:11434"
    roles:
      - chat
      - edit

tabAutocompleteModel:
  title: Qwen Autocomplete
  provider: ollama
  model: qwen2.5-coder:32b
  apiBase: "http://127.0.0.1:11434"
```

## Debugging

```bash
# SSH into the server
ssh -i ~/.ssh/ai-ssh-key.pem ubuntu@<SERVER_IP>

# Watch cloud-init setup progress (live)
sudo tail -f /var/log/ki-setup.log

# Check Ollama service
systemctl status ollama
sudo journalctl -u ollama -n 50 --no-pager

# List downloaded models
ollama list

# Check EVS volume mount
df -h /usr/share/ollama/.ollama/models
```

## OBS model storage

Models are automatically backed up to an OTC OBS bucket (`ollama-models-eu-de`) after the first download. On subsequent starts — even in a different AZ — models are loaded from OBS instead of the internet.

| Scenario | Source | Duration |
|----------|--------|----------|
| Same AZ restart | EVS volume (local) | ~3 min |
| Different AZ | OBS bucket (internal) | ~5–10 min |
| First boot ever | ollama.com (internet) | ~20–40 min |

The OBS bucket is managed by Terraform and created automatically on first `terraform apply`.

```bash
# Verify models are in OBS
aws configure set aws_access_key_id "$OS_ACCESS_KEY"
aws configure set aws_secret_access_key "$OS_SECRET_KEY"
aws s3 ls s3://ollama-models-eu-de/models/ --endpoint-url https://obs.eu-de.otc.t-systems.com
```

## Cost estimate (eu-de region)

| Resource | Cost |
|----------|------|
| p2s.2xlarge.8 (A100, 1x GPU) | ~4 €/hour (only while running) |
| EVS Volume 100 GB SSD | ~4–5 €/month (always) |
| OBS Bucket ~29 GB models | ~0.60 €/month (always) |
| Elastic IP | ~0 €/month (free when associated) |

> The server is only billed while running. Stop it with `./ki-stop.sh` when not in use.

## .gitignore

The `.gitignore` in this repo already excludes sensitive and generated files:

```
*.pem
*.pub
terraform.tfstate
terraform.tfstate.backup
.terraform/
.terraform.lock.hcl
```

## GPU flavors reference (OTC eu-de) see (https://www.t-cloud-public.com/en/prices/price-calculator)

| Flavor | GPU | VRAM | Use case | Status |
|--------|-----|------|----------|--------|
| `g6.4xlarge.4` | NVIDIA T4 | 16 GB | Models up to 14b | Available |
| `p2s.2xlarge.8` | NVIDIA A100 | 80 GB | Models up to 32b | **Recommended** |
| `p2v.2xlarge.8` | NVIDIA V100 | 16–32 GB | Models up to 14b | Available (NVLink) |
| `p5s.*` | NVIDIA H100 | 80 GB | Training / very large models | Available (EU-DE only) |
| `p3.*` | NVIDIA A100 | 80 GB | — | **Abandoned (Ecs.0019)** |
| `pi2.*` | NVIDIA T4 | 16 GB | — | **Abandoned, EOL 31.12.2026** |
| `g7v.*` | NVIDIA A40 | 48 GB (virt.) | — | Virtualized, capacity limited |

> **Note:** `qwen2.5-coder:72b` does not exist on Ollama. The largest available tag is `qwen2.5-coder:32b` (20 GB).
