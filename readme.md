# 🎮 SteamOS Custom Installer (Non-Destructive Custom Script)

This repository contains a custom script that allows you to install the **official SteamOS** alongside your existing **Windows 11** installation **without wiping the disk**.

It is designed to work with devices like the **Lenovo Legion Go** (or similar), and leverages the official SteamOS media to create a functional dual-boot system using the remaining unallocated space on your disk.

---

## ✅ What This Does

- Preserves your existing Windows installation.
- Installs SteamOS into the available unallocated space.
- Creates partitions automatically starting at a custom index.
- Configures SteamOS with dual rootfs (A/B setup) and var/home partitions.
- Finalizes GRUB bootloader via official `steamcl-install` flow.

---

## 💡 Before You Begin

> ⚠️ This script assumes Windows occupies partitions 1 through 4.  
> Adjust accordingly if your setup is different! Check Step 3 for more details.

---

## 🛠 Step-by-Step Installation

### 1️⃣ Boot with SteamOS USB Media

Download the official [SteamOS recovery image](https://store.steampowered.com/steamos/) and flash it to a USB drive. Boot your system using the USB stick into the **SteamOS desktop installer environment**.

---

### 2️⃣ Shrink the Windows Partition

Use a partition tool like:

- **Windows Disk Management** (before booting into SteamOS), or
- **GParted** (inside the installer)

...to shrink your existing Windows partition and leave **unallocated space** large enough to accommodate SteamOS (~12–15GB minimum).

---

### 3️⃣ Edit the Partition Indices (Optional)

If your Windows uses more than 4 partitions, or you've already added partitions, **edit the script** and change the indices accordingly to avoid overlap.
Open the script in a text editor and check the following values:

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

### 4️⃣ Final Step

Once in the SteamOS installer desktop:

1. Copy the script`steam-os-custom-install.sh` to your **Desktop**.
2. Open the terminal and apply execute permissions by run:
```bash
sudo chmod +x /Desktop/steam-os-custom-install.sh
```
3. Launch the installer from the terminal with:
```bash
sudo ./Desktop/steam-os-custom-install.sh
```

It will:

- Automatically create the required partitions in unallocated space.
- Format them correctly (FAT32 for ESP/EFI; EXT4 or BTRFS for the rest).
- Freeze the USB filesystem and copy it to rootfs-A/B.
- Finalize GRUB using `steamos-chroot` and `steamcl-install`.
- Reboot when done.

---

## 🔁 After Installation

- On reboot, your system should show a boot menu with **SteamOS** and **Windows** entries.
- If Windows isn’t detected, make sure `os-prober` is present or manually add the entry.
- You can also use the BIOS boot menu to select between Windows and the SteamOS bootloader.

---

## 📢 Notes

- **Data safety:** The script **does not overwrite** the Windows partition, but any disk operation carries risk. **Make backups.**
- **Advanced use only:** You are responsible for checking your existing partition layout.
- **UEFI-only:** This script assumes the system uses UEFI boot mode.
