#!/bin/bash
# uncomment to view debugging information
#set -xeuo pipefail

#check if we're root
if [[ "$UID" -ne 0 ]]; then
    echo "This script needs to be run as root!" >&2
    exit 3
fi

### Config options
target="/dev/nvme0n1"
efipart="/dev/nvme0n1p1"
swappart="/dev/nvme0n1p2"
rootpart="/dev/nvme0n1p3"
rootmnt="/mnt"
locale="en_US.UTF-8"
keymap="us"
timezone="America/New_York"
hostname="arch"
username="jc"
#SHA512 hash of password. To generate, run 'mkpasswd -m sha-512', don't forget to prefix any $ symbols with \ . The entry below is the hash of 'password'
#user_password="\$6\$/VBa6GuBiFiBmi6Q\$yNALrCViVtDDNjyGBsDG7IbnNR0Y/Tda5Uz8ToyxXXpw86XuCVAlhXlIvzy1M8O.DWFB6TRCia0hMuAJiXOZy/"
user_password="\$6\$KMjCZajVhYXNihUr\$AfqyGDmloZs.sEWUkdsmpbKoZqEks3tbJS5Xr9goUCoXXJa71hDtbL3ZTXxhfc34QOOJpounnO9peYoWhRQCy1"

#To fully automate the setup, change badidea=no to yes, and enter a cleartext password for the disk encryption

# badidea="no"
# crypt_password="1111"


### Packages to pacstrap ##
pacstrappacs=(
        base
        base-devel
        linux
        linux-firmware
        efibootmgr
        grub
        git
        neovim
        sudo
        networkmanager
        )
### Desktop packages #####
guipacs=(
        # gnome
        # gnome-tweaks
        # gdm
        # plasma
        # plasma-wayland-session
        # sddm
        # kitty
        # firefox
        # alacritty
        # nm-connection-editor
        # neofetch
        # sbctl
        )

# Partition
echo "Creating partitions..."
sgdisk -Z "$target"
sgdisk \
    -n1:0:+512M  -t1:ef00 -c1:EFISYSTEM \
    -n2::+2G     -t2:8400 -c2:swap \
    -N3          -t3:8304 -c3:linux \
    "$target"
# Reload partition table
sleep 2
partprobe -s "$target"
sleep 2
echo "Making File Systems..."
# Create file systems
mkfs.vfat -F32 -n EFISYSTEM /dev/disk/by-partlabel/EFISYSTEM
mkfs.ext4 -L linux "$rootpart"
# mount the root, and create + mount the EFI directory
echo "Mounting File Systems..."
mount "$rootpart" "$rootmnt"
mkdir "$rootmnt"/boot/efi -p
mount -t vfat /dev/disk/by-partlabel/EFISYSTEM "$rootmnt"/boot/efi
sleep 2
# mount & activating swap partition
echo "Activating & Mounting SWAP partition"
mkswap "$swappart"
swapon "$swappart"
sleep 2

#Update pacman mirrors and then pacstrap base install
echo "Pacstrapping..."
pacstrap -K $rootmnt "${pacstrappacs[@]}"
sleep 2

echo "Generating fstab file..."
genfstab -U $rootmnt >> "$rootmnt"/etc/fstab
sleep 2

echo "Setting up environment..."
#set up locale/env
#add our locale to locale.gen
sed -i -e "/^#"$locale"/s/^#//" "$rootmnt"/etc/locale.gen
#remove any existing config files that may have been pacstrapped, systemd-firstboot will then regenerate them
rm "$rootmnt"/etc/{machine-id,localtime,hostname,shadow,locale.conf} ||
systemd-firstboot --root "$rootmnt" \
	--keymap="$keymap" --locale="$locale" \
	--locale-messages="$locale" --timezone="$timezone" \
	--hostname="$hostname" --setup-machine-id \
	--welcome=false
arch-chroot "$rootmnt" locale-gen
echo "Configuring for first boot..."
#add the local user
arch-chroot "$rootmnt" useradd -G wheel -m -p "$user_password" "$username"
#uncomment the wheel group in the sudoers file
sed -i -e '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' "$rootmnt"/etc/sudoers
# #create a basic kernel cmdline, we're using DPS so we don't need to have anything here really, but if the file doesn't exist, mkinitcpio will complain
# echo "quiet rw" > "$rootmnt"/etc/kernel/cmdline
# #change the HOOKS in mkinitcpio.conf to use systemd hooks
# sed -i \
#     -e 's/base udev/base systemd/g' \
#     -e 's/keymap consolefont/sd-vconsole sd-encrypt/g' \
#     "$rootmnt"/etc/mkinitcpio.conf
# #change the preset file to generate a Unified Kernel Image instead of an initram disk + kernel
# sed -i \
#     -e '/^#ALL_config/s/^#//' \
#     -e '/^#default_uki/s/^#//' \
#     -e '/^#default_options/s/^#//' \
#     -e 's/default_image=/#default_image=/g' \
#     -e "s/PRESETS=('default' 'fallback')/PRESETS=('default')/g" \
#     "$rootmnt"/etc/mkinitcpio.d/linux.preset
#
# #read the UKI setting and create the folder structure otherwise mkinitcpio will crash
# declare $(grep default_uki "$rootmnt"/etc/mkinitcpio.d/linux.preset)
# arch-chroot "$rootmnt" mkdir -p "$(dirname "${default_uki//\"}")"
#
# #install the gui packages
# echo "Installing GUI..."
# arch-chroot "$rootmnt" pacman -Sy "${guipacs[@]}" --noconfirm --quiet
#
#
# #enable the services we will need on start up
# echo "Enabling services..."
# systemctl --root "$rootmnt" enable systemd-resolved systemd-timesyncd NetworkManager
# #mask systemd-networkd as we will use NetworkManager instead
# systemctl --root "$rootmnt" mask systemd-networkd
# #regenerate the ramdisk, this will create our UKI
# echo "Generating UKI and installing Boot Loader..."
# arch-chroot "$rootmnt" mkinitcpio -p linux
# echo "Setting up Secure Boot..."
# if [[ "$(efivar -d --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode)" -eq 1 ]]; then
# arch-chroot "$rootmnt" sbctl create-keys
# arch-chroot "$rootmnt" sbctl enroll-keys -m
# arch-chroot "$rootmnt" sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
# arch-chroot "$rootmnt" sbctl sign -s "${default_uki//\"}"
# else
# echo "Not in Secure Boot setup mode. Skipping..."
# fi
# #install the systemd-boot bootloader
# arch-chroot "$rootmnt" bootctl install --esp-path=/efi
# #lock the root account
# arch-chroot "$rootmnt" usermod -L root
# #and we're done
#
#
# echo "-----------------------------------"
# echo "- Install complete. Rebooting.... -"
# echo "-----------------------------------"
# sleep 10
# sync
# reboot