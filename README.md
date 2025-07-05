# 📁 File Integrity Monitor (fim-monitor)

A cross-distro Bash script to monitor file changes in a directory (and its subdirectories), identify the user/process responsible, and send desktop notifications.

🖥️ **Supports:** Debian/Ubuntu, Arch, Fedora, CentOS, openSUSE, and other Linux distributions.

---

## ✨ Features

- 📂 Real-time monitoring of `.txt` files (recursive)
- 👤 Identifies user and process responsible for file events
- 🔔 Desktop notifications for create/modify/delete/move
- 🕵️‍♂️ Audit log integration for detailed attribution
- ⚙️ Automatic dependency installation (cross-distro)
- 🧱 Robust logging and error handling

---

## 📦 Requirements

- ✅ Linux (any major distro)
- ⚠️ Root privileges (for audit logging and dependency installation)
- 🐚 Bash shell
- 🌐 Internet connection (for installing dependencies)

---

## 🚀 Installation

```bash
git clone git@github.com:benoumessad-mohamed-el-amine/file-monitoring-integrity-FIM-.git
cd file-monitoring-integrity-FIM-
chmod +x monitor.sh
