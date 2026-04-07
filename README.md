# 🔐 Encrypted Multi-Cloud Sync (rclone)

<p align="center">
  <strong>rclone • Bash • Encryption • Multi-Cloud • Backup Automation</strong>
</p>

---

## 🧰 Tech Stack

![rclone](https://img.shields.io/badge/rclone-3F79E0?logo=cloud&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-121011?logo=gnubash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)

---

## 📌 Project Overview

This project provides a **secure, automated system for encrypted file synchronization across multiple cloud providers** using `rclone`.

It is designed as a **reproducible, privacy-focused alternative to traditional cloud sync tools**, with:

* 🔐 End-to-end encryption (via rclone crypt remotes)
* ☁️ Multi-provider support (Google Drive, Dropbox, OneDrive, ProtonDrive, WebDAV, S3, etc.)
* 🔄 Bidirectional sync (local ↔ cloud)
* 📴 Offline-first behavior with pending-sync flags
* 💾 Automatic versioned backups (pre + post session)
* 📂 Dataset-based organization
* 🔓 Optional decrypted mount for seamless file access

---

## 📚 Table of Contents

* [Architecture](#-architecture)
* [Repository Structure](#-repository-structure)
* [Setup Instructions](#-setup-instructions)
* [Encryption Model](#-encryption-model)
* [Sync & Backup Logic](#-sync--backup-logic)
* [Dataset System](#-dataset-system)
* [Offline & Pending Mode](#-offline--pending-mode)
* [Usage Examples](#-usage-examples)
* [Reference Configs](#-reference-configs)
* [Security Considerations](#-security-considerations)
* [Future Improvements](#-future-improvements)
* [What This Project Demonstrates](#-what-this-project-demonstrates)

---

## 🏗 Architecture

```
Local Filesystem (~/data)
        ↓
rclone (crypt + alias remotes)
        ↓
Encrypted Cloud Storage
        ↓
Local + Cloud Backups (pre/post session)
        ↓
Optional Decrypted Mount (FUSE)
```

---

## 📂 Repository Structure

```
rclone-encrypted-sync/
│
├── scripts/
│   ├── auto-rclone-conf.sh   # interactive rclone config generator (8 remotes/provider)
│   ├── sstart.sh             # start session (sync or mount)
│   └── sstop.sh              # stop session (unmount + sync + backup)
│
├── configs/
│   ├── rclone.conf-example
│   └── rclone.conf-template
│
└── README.md
```

---

## ⚙️ Setup Instructions

### 1️⃣ Install dependencies

```
sudo pacman -S rclone
```

or:

```
sudo apt install rclone
```

### 2️⃣ Clone repository

```
git clone https://github.com/nibble-stack/sync-encrypt-script.git
cd sync-encrypt-script
```

### 3️⃣ Configure providers

```
./scripts/auto-rclone-conf.sh gdrive dropbox
```

or shorthand:

```
./scripts/auto-rclone-conf.sh gd db
```

The script will:

* Ask for provider type (drive, dropbox, onedrive, protondrive, webdav, s3, other)
* Create base remotes
* Generate **8 remotes per provider** (crypt + sync + backups)
* Create directory structure under `~/data/`
* Prompt for encryption password + salt (obscured)
* Support skip/overwrite for existing remotes (TTY-safe)

---

## 📂 Reference Configs

Located in `configs/`:

* `rclone.conf-example` – realistic example of generated remotes  
* `rclone.conf-template` – generic template for any provider  

These files are **reference only**.  
Always use `auto-rclone-conf.sh` to generate your actual config.

---

## 🔐 Encryption Model

Each provider gets **8 remotes**:

### Crypt (encrypted)
* prov-crypt-cloud  
* prov-crypt-local  
* prov-crypt-cloud-bak  
* prov-crypt-local-bak  

### Sync (plain)
* prov-sync-cloud  
* prov-sync-local  
* prov-sync-cloud-bak  
* prov-sync-local-bak  

All crypt remotes use:

* AES encryption (rclone crypt)
* Obscured password + salt (entered once per provider)

---

## 🔁 Sync & Backup Logic

### Start (sstart.sh)

```
./sstart.sh <provider> <dataset-id> --mount
./sstart.sh <provider> <dataset-id> --sync
```

### What happens:

#### 1. Directory creation  
Automatically creates:

```
~/data/sync/<provider>/<prov>-crypt/
~/data/sync/<provider>/<prov>-sync/
~/data/sync/<provider>/<prov>-decrypt/
~/data/sync/<provider>/<prov>-pending/
~/data/sync-backup/<provider>-bak/<prov>-crypt-bak/
~/data/sync-backup/<provider>-bak/<prov>-sync-bak/
```

#### 2. Pre-session backup  
* `--mount`: crypt + sync datasets  
* `--sync`: sync dataset only  

Backups stored under:

```
~/data/sync-backup/<provider>-bak/
```

#### 3. Sync logic  
If **online**:

* Pull cloud → local  
* Push local → cloud  
* (crypt + sync for mount mode, sync only for sync mode)

If **offline**:

* Creates pending flags in `<prov>-pending/`

#### 4. Optional mount  
`--mount` mode mounts decrypted view:

```
~/data/sync/<provider>/<prov>-decrypt/<prov>-decrypt-<id>
```

---

## 🛑 Stop Session (sstop.sh)

```
./sstop.sh <provider> <dataset-id>
```

### What happens:

1. Unmount decrypted dataset (if mounted)
2. If offline → exit early (sync deferred)
3. Sync local → cloud (crypt + sync)
4. Post-session backup (crypt + sync)

Backups are timestamped:

```
<prov>-crypt-bak-<id>-post-YYYYMMDD-HHMMSS
<prov>-sync-bak-<id>-post-YYYYMMDD-HHMMSS
```

---

## 📦 Dataset System

Each dataset is isolated by provider + ID:

```
~/data/sync/<provider>/
  ├── <prov>-crypt/<prov>-crypt-<id>
  ├── <prov>-sync/<prov>-sync-<id>
  ├── <prov>-decrypt/<prov>-decrypt-<id>
  └── <prov>-pending/
```

Example:

```
./sstart.sh gdrive 01 --mount
```

Creates:

```
gdrive-crypt-01
gdrive-sync-01
gdrive-decrypt-01
```

---

## 📴 Offline & Pending Mode

If offline:

* `sstart.sh` creates pending flags:
  ```
  <prov>-sync-pending-<id>
  <prov>-crypt-pending-<id>
  ```
* No cloud sync occurs
* Next online session will sync normally

---

## 🚀 Usage Examples

### Mount encrypted dataset

```
./sstart.sh gdrive 01 --mount
```

Decrypted files appear at:

```
~/data/sync/gdrive/gdrive-decrypt/gdrive-decrypt-01
```

### Sync-only mode

```
./sstart.sh gdrive 02 --sync
```

### Stop session

```
./sstop.sh gdrive 01
```

---

## 🔐 Security Considerations

* Encryption handled via rclone crypt  
* Password + salt are obscured  
* No credentials stored in repo  
* Local filesystem remains encrypted at rest (crypt workflow)  

⚠️ **Losing password/salt = permanent data loss**  
Store them securely.

---

## 🚀 Future Improvements

* systemd service integration  
* automatic scheduled sync (cron)  
* conflict resolution strategy  
* logging + monitoring  
* optional compression layer  
* CLI wrapper for easier UX  

---

## 🎯 What This Project Demonstrates

* Advanced rclone usage (crypt + alias remotes)  
* Secure multi-cloud architecture  
* Offline-first sync design  
* Backup strategies (pre/post session)  
* Bash automation for reproducible workflows  
* Practical privacy-focused engineering  
