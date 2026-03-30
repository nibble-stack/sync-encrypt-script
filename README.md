# 🔐 Encrypted Multi-Cloud Sync (rclone)

<p align="center">
  <strong>rclone • Bash • Encryption • Multi-Cloud • Backup Automation</strong>
</p>

---

## 🧰 Tech Stack

![rclone](https://img.shields.io/badge/rclone-3F79E0?logo=cloud\&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-121011?logo=gnubash\&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux\&logoColor=black)

---

## 📌 Project Overview

This project provides a **secure, automated system for encrypted file synchronization across multiple cloud providers** using `rclone`.

It is designed as a **reproducible, privacy-focused alternative to traditional cloud sync tools**, with:

* 🔐 End-to-end encryption (via rclone crypt remotes)
* ☁️ Multi-provider support (Google Drive, Dropbox, S3, etc.)
* 🔄 Bidirectional sync (local ↔ cloud)
* 📴 Offline-first behavior with deferred sync
* 💾 Automatic versioned backups
* 📂 Dataset-based organization
* 🔓 Optional decrypted mount for seamless file access

---

<details open>
  <summary><strong>📚 Table of Contents</strong></summary>

* Architecture
* Repository Structure
* Setup Instructions
* Encryption Model
* Sync & Backup Logic
* Dataset System
* Failure Handling
* Usage Examples
* Security Considerations
* Future Improvements
* What This Project Demonstrates

</details>

---

## 🏗 Architecture

```
Local Filesystem
       ↓
rclone (crypt)
       ↓
Encrypted Remote (Cloud Provider)
       ↓
Backup Rotation (Local + Cloud)
       ↓
Optional Decrypted Mount (FUSE)
```

---

## 📂 Repository Structure

```
rclone-encrypted-sync/
│
├── scripts/
│   ├── auto-rclone-conf.sh   # interactive rclone config generator
│   ├── sstart.sh             # start session (sync / mount)
│   └── sstop.sh              # stop session (sync + backup)
│
├── README.md
```

---

## ⚙️ Setup Instructions

### 1️⃣ Install dependencies

```
sudo pacman -S rclone
```

Or:

```
sudo apt install rclone
```

---

### 2️⃣ Clone repository

```
git clone https://github.com/nibble-stack/sync-encrypt-script.git
cd sync-encrypt-script
```

---

### 3️⃣ Configure providers

Run the setup script:

```
./scripts/auto-rclone-conf.sh gdrive dropbox

or

./scripts/auto-rclone-conf.sh gd db
```

This will:

* Create base remotes (via rclone)
* Generate encrypted (`crypt`) remotes
* Create sync + backup remotes
* Initialize directory structure
* Prompt for encryption password + salt

---

## 🔐 Encryption Model

Each provider gets multiple remotes:

### Encrypted (crypt)

* provider-crypt-cloud
* provider-crypt-local
* backup equivalents

Uses:

* AES encryption (via rclone)
* Obscured password + salt

---

### Sync (alias)

* provider-sync-cloud
* provider-sync-local

These are:

* Plain (non-encrypted)
* Used for staging / direct sync

---

## 🔁 Sync & Backup Logic

### Start (sstart.sh)

```
./sstart.sh <provider> <dataset-id> --mount|--sync
```

What happens:

1. Creates dataset directories
2. Ensures remote paths exist
3. Pre-session backup (local + cloud)
4. Sync logic:

   * If online → full sync
   * If offline → mark as pending
5. Upload local changes
6. Optional mount (encrypted datasets only)

---

### Stop (sstop.sh)

```
./sstop.sh <provider> <dataset-id>
```

What happens:

1. Unmount decrypted filesystem
2. Sync local → cloud
3. Post-session backup
4. Backup rotation (keep last 5)

---

## 📦 Dataset System

Each dataset is isolated:

```
~/sync/<provider>/
  ├── <provider>-crypt/
  ├── <provider>-sync/
  ├── <provider>-decrypt/
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

## 🧪 Failure Handling

### Offline Mode

* Detects connectivity via ping
* Defers sync using `.pending` flag
* Automatically resumes on next run

---

### Idempotency

* Safe to re-run scripts
* Existing remotes can be skipped or overwritten
* No duplicate configuration

---

### Backup Safety

* Pre + post session backups
* Stored locally and in cloud
* Automatic rotation (max 5 versions)

---

## 🚀 Usage Examples

### Mount encrypted dataset

```
./sstart.sh gdrive 01 --mount
```

Access decrypted files at:

```
~/sync/gdrive/gdrive-decrypt/gdrive-decrypt-01
```

---

### Sync-only mode

```
./sstart.sh gdrive 02 --sync
```

---

### Stop session

```
./sstop.sh gdrive 01
```

---

## 🔐 Security Considerations

* Encryption handled via rclone crypt
* Password + salt are obscured (not plaintext)
* No credentials stored in repo
* Local filesystem remains encrypted at rest (if using crypt workflow)

Important:

* Losing password/salt = permanent data loss
* Store them securely (e.g. password manager)

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
* Backup rotation strategies
* Bash automation for reproducible workflows
* Practical privacy-focused engineering

---

