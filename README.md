# 🔐 Encrypted Multi‑Cloud Sync  
### rclone • bisync • encryption • backups • Android support • offline‑first

<p align="center">
  <img src="https://img.shields.io/badge/rclone-3F79E0?logo=cloud&logoColor=white" />
  <img src="https://img.shields.io/badge/Bash-121011?logo=gnubash&logoColor=white" />
  <img src="https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black" />
  <img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white" />
</p>

---

## 🚀 Overview

This project is a **secure, encrypted, multi‑cloud synchronization system** built on:

- **rclone crypt** → end‑to‑end encryption  
- **rclone bisync** → bidirectional sync with conflict handling  
- **Local + cloud backups** → pre/post session  
- **Decrypted FUSE mount** → optional working directory  
- **Android shared‑storage mirroring** → Termux integration  
- **Offline‑aware behavior**  
- **Dataset‑based isolation**  
- **Dry‑run mode** for safe testing  

It is a **privacy‑focused alternative to commercial sync clients**, fully scriptable and cloud‑agnostic.

---

## 📚 Table of Contents

- [Architecture](#-architecture)
- [Repository Structure](#-repository-structure)
- [Setup](#-setup)
- [Directory Layout](#-directory-layout)
- [Remote Layout](#-remote-layout)
- [Encryption Model](#-encryption-model)
- [Sync & Backup Logic](#-sync--backup-logic)
- [Bisync Behavior](#-bisync-behavior)
- [Offline Mode](#-offline-mode)
- [Dry‑Run Mode](#-dry-run-mode)
- [Android Support](#-android-support)
- [Usage Examples](#-usage-examples)
- [Sync‑Only Datasets](#-synconly-datasets)
- [Browsing Backups](#-browsing-backups)
- [Security Considerations](#-security-considerations)
- [Future Improvements](#-future-improvements)
- [What This Project Demonstrates](#-what-this-project-demonstrates)

---

## 🏗 Architecture

```
Local Filesystem ($HOME/data)
        ↓
rclone remotes (crypt + alias)
        ↓
Encrypted Cloud Storage
        ↓
Local + Cloud Backups
        ↓
Optional Decrypted FUSE Mount
        ↓
Android Shared‑Storage Mirror (Termux)
```

---

## 📂 Repository Structure

```
rclone-encrypted-sync/
│
├── scripts/
│   ├── auto-rclone-conf.sh
│   ├── sstart.sh
│   ├── sstop.sh
│   └── core/
│       ├── android.sh
│       ├── env.sh
│       ├── utils.sh
│       ├── provider.sh
│       ├── paths.sh
│       ├── lock.sh
│       ├── backup.sh
│       ├── bisync.sh
│       └── mount.sh
│
├── configs/
│   ├── rclone.conf-example
│   └── rclone.conf-template
│
└── README.md
```

---

## 🛠 Setup

### 1️⃣ Install rclone

Linux:

```
sudo apt install rclone
# or
sudo pacman -S rclone
```

Android (Termux):

```
pkg install rclone
termux-setup-storage
```

### 2️⃣ Clone the repo

```
git clone https://github.com/nibble-stack/sync-encrypt-script.git
cd sync-encrypt-script
```

### 3️⃣ Generate remotes

```
./scripts/auto-rclone-conf.sh gdrive dropbox
```

Creates:

- 8 remotes per provider  
- Full directory structure  
- Encrypted + plain sync trees  
- Backup remotes  
- Password + salt prompts  

---

## 📂 Directory Layout

```
$HOME/data/
  ├── sync/
  │   └── <provider>/
  │       ├── crypt/
  │       ├── sync/
  │       └── decrypted/
  │
  └── sync-backup/
      └── <provider>-bak/
          ├── crypt/
          └── sync/
```

Android adds:

```
~/storage/shared/data/sync/<provider>/<dataset-id>
```

This is a **temporary decrypted mirror** for Android apps.

---

## 🔧 Remote Layout

Each provider gets 8 remotes:

### Crypt (encrypted)
- `<prov>-crypt-local`
- `<prov>-crypt-cloud`
- `<prov>-crypt-local-bak`
- `<prov>-crypt-cloud-bak`

### Sync (plain)
- `<prov>-sync-local`
- `<prov>-sync-cloud`
- `<prov>-sync-local-bak`
- `<prov>-sync-cloud-bak`

---

## 🔐 Encryption Model

- AES encryption via rclone crypt  
- Obscured password + salt  
- Same password/salt across all crypt remotes of a provider  

---

## 🔁 Sync & Backup Logic

### Start session

```
./sstart.sh <provider> <id> --mount
./sstart.sh <provider> <id> --sync
```

### Stop session

```
./sstop.sh <provider> <id>
```

### sstart.sh performs:

1. Lock acquisition  
2. Directory creation  
3. Connectivity check  
4. Pre‑backup  
5. Sync + bisync  
6. Optional decrypted mount  
7. Android mirroring (if Termux detected)  

### sstop.sh performs:

1. Unmount  
2. Android mirror → decrypted  
3. Re‑encrypt  
4. Sync + bisync  
5. Cleanup shared storage  
6. Release lock  

---

## 🔄 Bisync Behavior

```
rclone bisync <local>:<id> <cloud>:<id>
```

- Automatic first‑time `--resync`  
- Conflict suffix:  
  `.conflict-<device-id>-<timestamp>`  
- Device ID stored in:  
  `$HOME/.config/sync-device-id`  

---

## 📴 Offline Mode

### sstart.sh
- Skips sync/bisync  
- Still mounts decrypted view  

### sstop.sh
- Skips sync/bisync  
- Leaves lock in place  

---

## 🧪 Dry‑Run Mode

```
./sstart.sh gdrive 01 --mount --dry-run
./sstop.sh gdrive 01 --dry-run
```

Dry‑run:

- Prints actions  
- Does not sync  
- Does not mount  
- Does not modify data  

---

# 📱 Android Support

Android support is **automatic** — no flags required.

Termux cannot mount inside shared storage, and Android apps cannot access Termux private directories.  
To solve this, the system uses **two‑way mirroring**:

---

## ▶️ sstart.sh (Android)

1. Normal Linux workflow (sync → bisync → decrypt → mount)  
2. Mirror decrypted → shared storage:

```
~/data/sync/<prov>/decrypted/<id>
→
~/storage/shared/data/sync/<prov>/<id>
```

Android apps work on the mirrored copy.

---

## ⏹ sstop.sh (Android)

1. Mirror shared storage → decrypted:

```
~/storage/shared/data/sync/<prov>/<id>
→
~/data/sync/<prov>/decrypted/<id>
```

2. Re‑encrypt  
3. Sync + bisync  
4. Remove decrypted data from shared storage:

```
rm -rf ~/storage/shared/data/sync/<prov>/<id>
```

This ensures **no decrypted data is left behind**.

---

## 🚀 Usage Examples

Mount:

```
./sstart.sh gdrive 01 --mount
```

Stop:

```
./sstop.sh gdrive 01
```

Sync‑only:

```
./sstart.sh gdrive 02 --sync
```

---

## 📁 Sync‑Only Datasets

Create manually:

```
mkdir -p ~/data/sync/<provider>/sync/<id>
```

Then:

```
./sstart.sh <provider> <id> --sync
```

---

## 🗂 Browsing Backups

Encrypted backups require mounting:

```
./sbackup-mount.sh <provider> <id>
```

Unmount:

```
./sbackup-unmount.sh <provider> <id>
```

---

## 🔐 Security Considerations

- rclone crypt handles encryption  
- Password + salt are obscured  
- No credentials stored in repo  
- Android shared storage is **not encrypted**  
- Shared storage is cleaned automatically  
- Losing password/salt = permanent data loss  

---

## 🚀 Future Improvements

- systemd integration  
- scheduled sync  
- Android background service  
- backup diff/restore tools  
- compression layer  

---

## 🎯 What This Project Demonstrates

- Advanced rclone usage  
- Secure multi‑cloud architecture  
- Offline‑aware sync design  
- Automated backup strategy  
- Bash automation  
- Practical privacy‑focused engineering  
