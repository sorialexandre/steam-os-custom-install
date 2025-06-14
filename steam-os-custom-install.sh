#!/bin/bash
set -eu

##############################################################################
# Utility Functions
##############################################################################
die() { echo >&2 "!! $*"; exit 1; }
cmd() { echo >&2 "+ $*"; "$@"; }
log() { echo >&2 "[INFO] $*"; }

# Zenity-based prompt for user confirmation
prompt_step() {
  local title="$1" msg="$2" unconditional="${3-}"
  if [[ ! ${unconditional:-} && ${NOPROMPT:-} ]]; then
    echo -e "$msg"
    return 0
  fi
  zenity --title "$title" --question --ok-label "Proceed" --cancel-label "Cancel" --no-wrap --text "$msg"
  [[ $? = 0 ]] || exit 1
}

prompt_reboot() {
  local msg="$1"
  local mode="reboot"
  [[ ${POWEROFF:-} ]] && mode="shutdown"
  prompt_step "Action Successful" "${msg}\n\nChoose Proceed to ${mode} now, or Cancel to stay in the repair image." "${REBOOTPROMPT:-}"
  [[ $? = 0 ]] || exit 1
  if [[ ${POWEROFF:-} ]]; then
    cmd systemctl poweroff
  else
    cmd systemctl reboot
  fi
}

##############################################################################
# Configuration – Change these values as needed
##############################################################################

# Target disk – be very careful with this.
DISK=/dev/nvme0n1
DISK_SUFFIX="p"   # Adjust if your disk device does not use a 'p' suffix (e.g. /dev/sda1)

# Partition sizes in MiB for SteamOS:
PART_SIZE_ESP="256"
PART_SIZE_EFI="64"
PART_SIZE_ROOT="5120"
PART_SIZE_VAR="256"
PART_SIZE_HOME="100"

# Custom partition indices (so that we don’t rework the entire disk dialog)
# In "custom" mode these indices come from unallocated space.
FS_ESP=5
FS_EFI_A=6
FS_EFI_B=7
FS_ROOT_A=8
FS_ROOT_B=9
FS_VAR_A=10
FS_VAR_B=11
FS_HOME=12

##############################################################################
# Functions to Create and Format Custom SteamOS Partitions
##############################################################################

# Use sgdisk to add a partition only if it does not already exist (by its GPT label)
create_custom_parts() {
  # create_part takes: index, label, size (in MiB), and type GUID.
  create_part() {
    local index="$1" label="$2" size="$3" type="$4"
    # Check if a partition with this label already exists
    if ! lsblk -o PARTLABEL -nr "$DISK" | grep -qx "$label"; then
      log "Creating partition '$label' at index $index (${size}MiB)..."
      cmd sgdisk --new="${index}":0:+${size}M --change-name="${index}":"${label}" --typecode="${index}":"${type}" "$DISK"
      cmd partprobe "$DISK"
      sleep 2
    else
      log "Partition '$label' already exists; skipping."
    fi
  }

  create_part "$FS_ESP" "esp" "$PART_SIZE_ESP" "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
  create_part "$FS_EFI_A" "efi-A" "$PART_SIZE_EFI" "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
  create_part "$FS_EFI_B" "efi-B" "$PART_SIZE_EFI" "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
  create_part "$FS_ROOT_A" "rootfs-A" "$PART_SIZE_ROOT" "4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
  create_part "$FS_ROOT_B" "rootfs-B" "$PART_SIZE_ROOT" "4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
  create_part "$FS_VAR_A" "var-A" "$PART_SIZE_VAR" "4D21B016-B534-45C2-A9FB-5C16E091FD2D"
  create_part "$FS_VAR_B" "var-B" "$PART_SIZE_VAR" "4D21B016-B534-45C2-A9FB-5C16E091FD2D"
  create_part "$FS_HOME" "home" "$PART_SIZE_HOME" "933AC7E1-2EB4-4F13-B844-0E14E2AEF915"
}

# Format functions (using sudo)
fmt_ext4()  { cmd sudo mkfs.ext4 -F -L "$1" "$2"; }
fmt_fat32() { cmd sudo mkfs.vfat -F32 -n "$1" "$2"; }

##############################################################################
# Lower-Level Functions
##############################################################################

# diskpart returns the device path for a given partition index
diskpart() { echo "$DISK$DISK_SUFFIX$1"; }

# Copies the entire root (from the installer USB) to the target partition.
# (dd is used here; replace with rsync/tar if desired.)
imageroot() {
  local src="$1" target="$2"
  log "Copying from $src to $target..."
  cmd dd if="$src" of="$target" bs=128M status=progress oflag=sync
  cmd btrfstune -f -u "$target"  # Update UUID to avoid duplication issues
  cmd btrfs check "$target"
}

# Set up boot configuration in the target partition set.
finalize_part() {
  local partset="$1"
  log "Finalizing boot configuration for partset $partset..."
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset "$partset" -- mkdir /efi/SteamOS
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset "$partset" -- mkdir -p /esp/SteamOS/conf
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset "$partset" -- steamos-partsets /efi/SteamOS/partsets
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset "$partset" -- steamos-bootconf create --image "$partset" --conf-dir /esp/SteamOS/conf --efi-dir /efi --set title "$partset"
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset "$partset" -- grub-mkimage
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset "$partset" -- update-grub
}

##############################################################################
# Main Repair/Installation Function
##############################################################################
repair_steps() {
  # Format the var partitions first
  log "Formatting 'var' partitions..."
  fmt_ext4 var "$(diskpart $FS_VAR_A)"
  fmt_ext4 var "$(diskpart $FS_VAR_B)"

  # Create boot partitions
  if [[ $writeOS = 1 ]]; then
    log "Formatting boot partitions..."
    fmt_fat32 esp "$(diskpart $FS_ESP)"
    fmt_fat32 efi "$(diskpart $FS_EFI_A)"
    fmt_fat32 efi "$(diskpart $FS_EFI_B)"
  fi

  if [[ $writeHome = 1 ]]; then
    log "Formatting home partition..."
    cmd sudo mkfs.ext4 -F -O casefold -T huge -L home "$(diskpart $FS_HOME)"
    cmd tune2fs -m 0 "$(diskpart $FS_HOME)"
  fi

  # BIOS update staging is skipped here for brevity (remove unused functions)

  # Find the installer root device (usually the USB installer’s root)
  local rootdevice
  rootdevice="$(findmnt -n -o source /)"
  if [[ -z "$rootdevice" || ! -e "$rootdevice" ]]; then
    die "Could not find the USB installer root. Check your installation media."
  fi

  log "Freezing the installer root filesystem..."
  # Freeze filesystem for a consistent snapshot
  fsfreeze -f /

  log "Imaging OS partition A..."
  imageroot "$rootdevice" "$(diskpart $FS_ROOT_A)"

  log "Imaging OS partition B..."
  imageroot "$rootdevice" "$(diskpart $FS_ROOT_B)"

  fsfreeze -u /

  log "Finalizing boot configurations for partsets A and B..."
  finalize_part A
  finalize_part B

  log "Finalizing EFI system partition..."
  cmd steamos-chroot --no-overlay --disk "$DISK" --partset A -- steamcl-install --flags restricted --force-extra-removable
}

##############################################################################
# Main – Custom Installation Branch
##############################################################################

# The "custom" branch creates a new set of SteamOS partitions at custom indices
# without wiping the whole disk.
prompt_step "Custom SteamOS Install" "This action installs SteamOS on this device (without wiping the entire disk) by creating a new set of partitions starting at index $FS_ESP.\nWARNING: Ensure that sufficient unallocated space exists and you understand the risks."
writePartitionTable=0  # Do NOT re-write the entire partition table
writeOS=1
writeHome=1

# Create the custom partitions (if not already present)
create_custom_parts

# Run the repair/installation steps
repair_steps

prompt_reboot "Custom Install complete."
