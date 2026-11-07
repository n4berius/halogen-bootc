# halOS guided install (#42): the first boot menu entry. plan-install picks the disk and asks
# for encryption, root and the admin user, then this kickstart installs with no more questions.
# The custom partitioning entry still opens the full graphical installer.
text
lang en_US.UTF-8
keyboard us
timezone Etc/UTC --utc
%include /tmp/halos-plan.ks
bootc --source-imgref containers-storage:@TARGET_IMAGE@ --target-imgref @TARGET_IMAGE@

%pre --erroronfail --interpreter=/usr/bin/bash
# Only emergencies on the screen while questions and passwords are typed.
dmesg -n 1 || true
if blkid -L HALOS_ANSWERS >/dev/null 2>&1; then
  # The VM test: answers on a volume, nothing typed. Its messages go to the serial log.
  out=/dev/console; [ -w /dev/ttyS0 ] && out=/dev/ttyS0
  /usr/libexec/halos/plan-install /tmp/halos-plan.ks < /dev/null > "$out" 2>&1
  exit
fi
# The questions get console 8 to themselves, away from the installer's own output. Not 2 to 6:
# switching to those makes logind start Anaconda's root shell there (autovt@, NAutoVTs=6), which
# would read the same keystrokes.
chvt 8 || true
/usr/libexec/halos/plan-install /tmp/halos-plan.ks < /dev/tty8 > /dev/tty8 2>&1
rc=$?
chvt 1 || true
exit $rc
%end
