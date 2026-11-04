# Only the OS source is preset, so the installer asks about disks, encryption and users.
bootc --source-imgref containers-storage:@TARGET_IMAGE@ --target-imgref @TARGET_IMAGE@
