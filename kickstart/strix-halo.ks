# ERASES nvme0n1. Encrypted LVM layout for a new Strix Halo appliance.
# Before use, replace the SSH key. The installer asks for the LUKS passphrase.
text
lang en_US.UTF-8
keyboard us
timezone Etc/UTC --utc
network --bootproto=dhcp --device=link --activate --hostname=strix-halo
selinux --enforcing
rootpw --lock
user --name=naberius --groups=wheel --lock
sshkey --username=naberius "REPLACE_WITH_YOUR_SSH_PUBLIC_KEY"

ignoredisk --only-use=nvme0n1
clearpart --all --initlabel --disklabel=gpt --drives=nvme0n1
reqpart --add-boot
part pv.01 --size=1 --grow --ondisk=nvme0n1 --encrypted --luks-version=luks2
volgroup vg0 pv.01
logvol /              --vgname=vg0 --name=root     --size=40960  --fstype=xfs
logvol /var           --vgname=vg0 --name=var      --size=102400 --fstype=xfs
logvol /var/log       --vgname=vg0 --name=log      --size=10240  --fstype=xfs
logvol /var/log/audit --vgname=vg0 --name=audit    --size=5120   --fstype=xfs
logvol /var/tmp       --vgname=vg0 --name=tmp      --size=10240  --fstype=xfs
logvol /var/home      --vgname=vg0 --name=home     --size=20480  --fstype=xfs
logvol /var/srv       --vgname=vg0 --name=srv      --size=204800 --grow --fstype=xfs

# Repeated here because a kickstart install may not apply kargs.d on first boot.
bootloader --append="amdgpu.gttsize=126976 ttm.pages_limit=32505856 iommu=pt"
ostreecontainer --url=ghcr.io/n4berius/halogen-flash-bootc:0.18.23 --no-signature-verification
reboot
