# 🎮 SteamOS Custom Installer (Non-Destructive)

This repository provides a **custom SteamOS installation script** that allows users to **preserve Windows**, **wipe the disk entirely**, or **manually configure partition indices** for maximum flexibility.

It is designed to work with devices like the **Lenovo Legion Go** (or similar), and leverages the official SteamOS media to create a functional dual-boot system using the remaining unallocated space on your disk.

---

## ✅ What This Script Does

- **Creates SteamOS partitions automatically** or lets users **manually define partition indices**.
- **Preserves Windows** unless the user selects full disk wipe.
- **Allows full disk wipe** for a clean SteamOS-only install.
- **Properly installs and configures the bootloader** using GRUB.
- **Detects Windows automatically** and ensures proper dual-boot setup.

---

## ⚠️ Before You Begin

- **Backup Your Data:** Any disk operation carries risk **Make backups!** Selecting "full disk wipe" will erase everything.
- **UEFI Boot Mode Required:** Legacy BIOS setups may require additional steps.
- **Windows Users:** If you want dual boot, **do not select full wipe**.

---

## 🛠 Step-by-Step Installation

### 1️⃣ Boot with SteamOS USB Media

Download the official [SteamOS recovery image](https://store.steampowered.com/steamos/) and flash it to a USB drive. Boot your system using the USB stick into the **SteamOS desktop installer environment**.

---

### 2️⃣ Shrink the Windows Partition (Optional)
    Use a partition tool like:

    - **GParted** (inside the SteamOS installer), or
    - **Windows Disk Management** (before booting into SteamOS)

    ...to shrink your existing Windows partition and leave **unallocated space** large enough to accommodate SteamOS (~12–15GB minimum).

---

### 3️⃣ Launch Installation

Once in the SteamOS installer desktop:

1. Copy the script`steam-os-custom-install.sh` to your **Desktop**.
2. Open the terminal and apply execute permissions by run:
```bash
sudo chmod +x ./Desktop/steam-os-custom-install.sh
```
3. Launch the installer from the terminal with:
```bash
sudo ./Desktop/steam-os-custom-install.sh
```

---

### 4️⃣ During Installation

The script offers **three installation modes**:

1. **Full Disk Wipe** → **Deletes all partitions** and sets up SteamOS from scratch.
2. **Preserve Partitions** → Uses available free space for SteamOS while keeping Windows intact.
3. **Manual Partition Indexing** → **User selects partition numbers**, ensuring compatibility with custom layouts.

If choosing **manual indexing**, you’ll be prompted to enter partition indices. Example, assuming Windows occupies partitions 1 through 4, choose as follow:

```bash
FS_ESP=5
FS_EFI_A=6
FS_EFI_B=7
FS_ROOT_A=8
FS_ROOT_B=9
FS_VAR_A=10
FS_VAR_B=11
FS_HOME=12
```
---

## 🔄 Post-Installation

- **GRUB automatically detects Windows** (if enabled).
- **SteamOS boots securely**.
- **Boot order can be adjusted via EFI if needed**.

---

## ⚠️ Disclaimer

- **Full wipe mode erases everything**—use cautiously.
- This script **does not remove Windows** unless full wipe is chosen.
- If boot fails, **manual EFI repair may be needed** using a Windows recovery USB.