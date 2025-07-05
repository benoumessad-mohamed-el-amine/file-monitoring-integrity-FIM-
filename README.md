# 📁 File Integrity Monitor (fim-monitor)

A cross-distro Bash script to monitor file changes in a directory (and its subdirectories), identify the user/process responsible, and send desktop notifications.

🖥️ **Supports:** Debian/Ubuntu, Arch, Fedora, CentOS, openSUSE, kali, and other Linux distributions.

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

## 🚀 Quick Start

```bash
sudo bash monitor.sh [directory_to_monitor]
```
- If no directory is specified, the current directory is monitored.

---

## 🛠️ Usage

- Monitors all `.txt` files by default (can be customized in the script).
- Sends desktop notifications for file creation, modification, deletion, and moves.
- Logs all events to `.file_monitor.log` in the monitored directory.

**Example:**
```
sudo bash monitor.sh /home/user/Documents
```

**Sample Output:**
```
========================================
   🛡️  File Integrity Monitor Started   
========================================
Monitoring directory: /home/user/Documents
File monitoring active. Press Ctrl+C to stop.
```

---

## 🖼️ Screenshots

> _Add screenshots or terminal output here to showcase notifications and logs._

---

## ⚙️ How It Works
- Uses `inotifywait` for real-time file event monitoring.
- Integrates with `auditd` to attribute file changes to users and processes.
- Sends notifications using `notify-send` (if available).
- Maintains a hash baseline for integrity checking.

---

## 🔧 Customization
- To monitor different file types, change `find . -type f -name "*.txt"` in the script.
- Log and hash file locations can be adjusted by editing the `LOG_FILE` and `HASH_FILE` variables.

---

## ❓ Troubleshooting & FAQ
- **Q:** _Script fails to start auditd or install dependencies?_
  - **A:** Ensure you run as root and have an internet connection.
- **Q:** _No notifications?_
  - **A:** Make sure `notify-send` is installed and you are running a graphical session.
- **Q:** _How to monitor other file types?_
  - **A:** Edit the script and change the file pattern in the `find` and `inotifywait` commands.

---

## 🤝 Contributing
Pull requests and suggestions are welcome! Please open an issue or submit a PR.

---

## 📄 License
MIT License. See `LICENSE` file for details.
