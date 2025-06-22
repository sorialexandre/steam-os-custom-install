#!/bin/bash
set -eu

##############################################################################
# Utility Functions
##############################################################################
die() {
  echo >&2 "!! $*"
  exit 1
}
cmd() {
  echo >&2 "+ $*"
  "$@"
}
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

# return sanitize state (and echo the current percentage complete)
# 0 : ready to sanitize
# 1 : sanitize in progress (echo the current percentage)
# 2 : drive does not support sanitize
#
get_sanitize_progress() {
  status=$(nvme sanitize-log "${DISK}" | grep "(SSTAT)" | grep -oEi "(0x)?[[:xdigit:]]+$") || return 2
  [[ $((status % 8)) -eq 2 ]] || return 0

  progress=$(nvme sanitize-log "${DISK}" | grep "(SPROG)" | grep -oEi "(0x)?[[:xdigit:]]+$") || return 2
  echo "sanitize progress: $(((progress * 100) / 65535))%"
  return 1
}

# call nvme sanitize, blockwise, and wait for it to complete.
#
sanitize_all() {
  sres=0
  get_sanitize_progress || sres=$?
  case $sres in
  0)
    echo
    echo "Warning!"
    echo
    echo "This action irrevocably clears *all* user data from ${DISK}"
    echo "Pausing five seconds in case you didn't mean to do this..."
    sleep 5
    echo "Ok, let's go. Sanitizing ${DISK}:"
    nvme sanitize -a 2 "${DISK}"
    echo "Sanitize action started."
    ;;
  1)
    echo "An NVME sanitize action is already in progress."
    ;;
  2) # use NVME secure-format since this device does not appear to support sanitize
    nvme format "${DISK}" -n 1 -s 1 -r
    return 0
    ;;
  *)
    echo "Unexpected result from sanitize-log"
    return $sres
    ;;
  esac

  while ! get_sanitize_progress; do
    sleep 5
  done

  echo "... sanitize done."
}

##############################################################################
# Configuration – Change these values as needed
##############################################################################
prompt_step "Custom SteamOS Install" \
  "This action installs SteamOS on this device. You can either wipe the entire disk or create new partitions by specifying their indices.\n\nWARNING: Ensure that sufficient unallocated space exists and you understand the risks."

# Target disk – be very careful with this.
DISK=/dev/nvme0n1
DISK_SUFFIX="p" # Adjust if your disk device does not use a 'p' suffix (e.g. /dev/sda1)

# Partition sizes in MiB for SteamOS:
PART_SIZE_ESP="256"
PART_SIZE_EFI="64"
PART_SIZE_ROOT="5120"
PART_SIZE_VAR="256"
PART_SIZE_HOME="100"

# Disk Setup
if zenity --question \
  --title="Disk Setup Options" \
  --text="Do you want to wipe the entire disk before installing SteamOS?\n\nSelecting 'No' will require you to manually specify partition indices."; then
  if zenity --question \
    --title="Confirm Disk Wipe" \
    --text="⚠️ WARNING: This will erase ALL DATA on the disk! \n\nAre you absolutely sure you want to continue?"; then

    sanitize_all
    writePartitionTable=1 # Enable full disk wipe
    FS_ESP=1
    FS_EFI_A=2
    FS_EFI_B=3
    FS_ROOT_A=4
    FS_ROOT_B=5
    FS_VAR_A=6
    FS_VAR_B=7
    FS_HOME=8
  else
    log "Disk wipe canceled by user."
    exit 1 # Abort operation if user cancels
  fi
else
  writePartitionTable=0 # Keep existing partitions and require manual indices

  # Require user to enter partition indices with default values
  FS_ESP=$(zenity --entry --title="Configure ESP" --text="Enter index for ESP partition:" --entry-text="5") || exit 1
  FS_EFI_A=$(zenity --entry --title="Configure EFI-A" --text="Enter index for EFI-A partition:" --entry-text="6") || exit 1
  FS_EFI_B=$(zenity --entry --title="Configure EFI-B" --text="Enter index for EFI-B partition:" --entry-text="7") || exit 1
  FS_ROOT_A=$(zenity --entry --title="Configure rootfs-A" --text="Enter index for rootfs-A partition:" --entry-text="8") || exit 1
  FS_ROOT_B=$(zenity --entry --title="Configure rootfs-B" --text="Enter index for rootfs-B partition:" --entry-text="9") || exit 1
  FS_VAR_A=$(zenity --entry --title="Configure var-A" --text="Enter index for var-A partition:" --entry-text="10") || exit 1
  FS_VAR_B=$(zenity --entry --title="Configure var-B" --text="Enter index for var-B partition:" --entry-text="11") || exit 1
  FS_HOME=$(zenity --entry --title="Configure Home" --text="Enter index for home partition:" --entry-text="12") || exit 1
fi

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
fmt_ext4() { cmd sudo mkfs.ext4 -F -L "$1" "$2"; }
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
  cmd btrfstune -f -u "$target" # Update UUID to avoid duplication issues
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
  if [[ $writePartitionTable = 1 ]]; then
    estat "Write known partition table"
    echo "$PARTITION_TABLE" | sfdisk "$DISK"
  fi

  # Format the var partitions first
  log "Formatting 'var' partitions..."
  fmt_ext4 var "$(diskpart $FS_VAR_A)"
  fmt_ext4 var "$(diskpart $FS_VAR_B)"

  # Create boot partitions
  log "Formatting boot partitions..."
  fmt_fat32 esp "$(diskpart $FS_ESP)"
  fmt_fat32 efi "$(diskpart $FS_EFI_A)"
  fmt_fat32 efi "$(diskpart $FS_EFI_B)"

  log "Formatting home partition..."
  cmd sudo mkfs.ext4 -F -O casefold -T huge -L home "$(diskpart $FS_HOME)"
  cmd tune2fs -m 0 "$(diskpart $FS_HOME)"

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

# Create the custom partitions (if not already present)
create_custom_parts

# Run the repair/installation steps
repair_steps

prompt_reboot "Custom Install complete."
