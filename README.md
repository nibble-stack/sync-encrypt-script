# 🔐 Encrypted Multi‑Cloud Sync (rclone + bisync)

<p align="center">
  <strong>rclone • bisync • Bash • Encryption • Multi‑Cloud • Backup Automation</strong>
</p>

---

## 🧰 Tech Stack

![rclone](https://img.shields.io/badge/rclone-3F79E0?logo=cloud&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-121011?logo=gnubash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)

---

## 📌 Project Overview

This project provides a **secure, automated, encrypted multi‑cloud synchronization system** built on top of:

- **rclone crypt** (end‑to‑end encryption)
- **rclone bisync** (bidirectional sync with conflict handling)
- **Local + cloud backups** (pre/post session)
- **Encrypted local storage** with optional decrypted FUSE mount
- **Dataset‑based isolation**
- **Offline‑aware behavior**
- **Reproducible configuration** via an interactive generator

The system is designed as a **privacy‑focused alternative to commercial sync clients**, while remaining transparent, scriptable, and cloud‑agnostic.

---

## 📚 Table of Contents

- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Setup Instructions](#setup-instructions)
- [Directory Layout](#directory-layout)
- [Remote Layout](#remote-layout)
- [Encryption Model](#encryption-model)
- [Sync & Backup Logic](#sync--backup-logic)
- [Bisync Behavior](#bisync-behavior)
- [Offline Mode](#offline-mode)
- [Usage Examples](#usage-examples)
- [Security Considerations](#security-considerations)
- [Future Improvements](#future-improvements)
- [What This Project Demonstrates](#what-this-project-demonstrates)

---

## 🏗 Architecture

```
Local Filesystem ($HOME/data)
        ↓
rclone remotes (crypt + alias)
        ↓
Encrypted Cloud Storage
        ↓
Pre/Post Backups (local + cloud)
        ↓
Optional Decrypted Mount (FUSE)
```

---

## 📂 Repository Structure

```
rclone-encrypted-sync/
│
├── scripts/
│   ├── auto-rclone-conf.sh   # interactive config generator (new DATA_ROOT layout)
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

### 3️⃣ Generate rclone remotes

```
./scripts/auto-rclone-conf.sh gdrive dropbox
```

or shorthand:

```
./scripts/auto-rclone-conf.sh gd db
```

The script will:

- Ask for provider type (drive, dropbox, onedrive, protondrive, webdav, s3, other)
- Create or overwrite the **base remote** (`<prov>`)
- Generate **8 remotes per provider** (crypt + sync + backups)
- Create the full directory structure under `$HOME/data`
- Prompt for encryption password + salt (obscured)
- Use TTY‑safe prompts for skip/overwrite decisions

---

## 📂 Directory Layout

The new layout is **DATA_ROOT‑aware**:

```
$HOME/data/
  ├── sync/
  │   └── <provider>/
  │       ├── crypt/
  │       ├── sync/
  │       ├── decrypted/
  │       └── pending/
  │
  └── sync-backup/
      └── <provider>-bak/
          ├── crypt/
          └── sync/
```

Each dataset is stored inside its remote as:

```
<remote>:<dataset-id>
```

Example:

```
gdrive-crypt-local:01
gdrive-sync-cloud:01
```

---

## 🔧 Remote Layout (8 remotes per provider)

For provider `gdrive`, the following remotes are created:

### Crypt (encrypted)
- `gdrive-crypt-cloud`
- `gdrive-crypt-local`
- `gdrive-crypt-cloud-bak`
- `gdrive-crypt-local-bak`

### Sync (plain)
- `gdrive-sync-cloud`
- `gdrive-sync-local`
- `gdrive-sync-cloud-bak`
- `gdrive-sync-local-bak`

Cloud remotes point to:

```
<prov>:data/sync/<prov>/{crypt,sync}
<prov>:data/sync-backup/<prov>-bak/{crypt,sync}
```

Local remotes point to:

```
/home/<user>/data/sync/<prov>/{crypt,sync}
/home/<user>/data/sync-backup/<prov>-bak/{crypt,sync}
```

---

## 🔐 Encryption Model

All crypt remotes use:

- AES encryption (rclone crypt)
- Obscured password + salt
- Same password/salt for all 4 crypt remotes of a provider

---

## 🔁 Sync & Backup Logic

### Start session

```
./sstart.sh <provider> <dataset-id> --mount
./sstart.sh <provider> <dataset-id> --sync
```

### Stop session

```
./sstop.sh <provider> <dataset-id>
```

### What happens during **sstart**:

1. **Lock acquisition**  
   Prevents concurrent sessions.

2. **Directory creation**  
   Ensures all required paths exist.

3. **Connectivity check**  
   If offline → skip sync, only mount if requested.

4. **Dataset existence logic**  
   For each dataset (crypt + sync):
   - If only local exists → backup local → sync up → backup cloud → bisync
   - If only cloud exists → backup cloud → sync down → backup local → bisync
   - If both exist → pre‑backups → bisync
   - If neither exists → skip

5. **Mount (if --mount)**  
   Mounts decrypted view:

   ```
   $HOME/data/sync/<prov>/decrypted/<id>
   ```

---

## 🛑 Stop Session Logic (sstop.sh)

`sstop.sh` performs:

1. **Unmount decrypted dataset** (if mounted)
2. **Connectivity check**
   - If offline → exit early (lock remains)
3. **Post‑session sync + bisync**
   - crypt dataset
   - sync dataset
4. **Post‑session backups**
   Stored under:

   ```
   <remote>-bak:<id>/post/<timestamp>
   ```
5. **Backup rotation**
   Keeps the newest 5 backups per dataset per remote.
6. **Lock removal**

---

## 🔄 Bisync Behavior

Both `sstart.sh` and `sstop.sh` use:

```
rclone bisync <local>:<id> <cloud>:<id>
```

With:

- Automatic first‑time `--resync`
- Conflict suffix:

```
.conflict-<device-id>-<timestamp>
```

Device ID is stored in:

```
$HOME/.config/sync-device-id
```

---

## 📴 Offline Mode

If offline:

- `sstart.sh`:
  - Skips all sync/bisync
  - Still mounts decrypted view if `--mount`
- `sstop.sh`:
  - Skips sync/bisync
  - Leaves lock file in place

Pending markers are no longer used (replaced by bisync logic).

---

## 🚀 Usage Examples

### Mount encrypted dataset

```
./sstart.sh gdrive 01 --mount
```

Decrypted files appear at:

```
~/data/sync/gdrive/decrypted/01
```

### Sync‑only mode

```
./sstart.sh gdrive 02 --sync
```

### Stop session

```
./sstop.sh gdrive 01
```

---

## 🔐 Security Considerations

- Encryption handled via rclone crypt  
- Password + salt are obscured  
- No credentials stored in repo  
- Local filesystem remains encrypted at rest  
- Backups include metadata.json for traceability  
- Losing password/salt = **permanent data loss**

---

## 🚀 Future Improvements

- systemd service integration  
- scheduled sync (cron/timers)  
- improved conflict resolution UI  
- logging + monitoring  
- optional compression layer  
- CLI wrapper for easier UX  

---

## 🎯 What This Project Demonstrates

- Advanced rclone usage (crypt + alias + bisync)
- Secure multi‑cloud architecture
- Offline‑aware sync design
- Automated backup strategy (pre/post)
- Bash automation for reproducible workflows
- Practical privacy‑focused engineering
