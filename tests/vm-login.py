"""Log in at a VM console through the QEMU monitor and capture a report on serial.

Usage: vm-login.py monitor.sock serial.log out-dir [plain|luks|luks-stale|luks-enroll|tpm]
  luks         type the disk passphrase, which must be asked for
  luks-stale   as luks, then enroll the TPM against a changed PCR 7 (as if the Secure Boot
               state later changed) and power off, leaving a binding that won't unlock
  luks-enroll  as luks, then bind the disk to the TPM with halogen-enroll-tpm and power off
  tpm          fail if the passphrase is asked for: the TPM must unlock the disk by itself
"""
import pathlib, re, socket, subprocess, sys, time

sock_path, serial, out = sys.argv[1:4]
mode = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else "plain"
luks = mode in ("luks", "luks-stale", "luks-enroll")
asked = False
serial, out = pathlib.Path(serial), pathlib.Path(out)
KEYS = {" ": "spc", "-": "minus", "=": "equal", ".": "dot", "/": "slash", ";": "semicolon",
        ",": "comma", "'": "apostrophe", "\n": "ret",
        "[": "bracket_left", "]": "bracket_right", "\\": "backslash"}
SHIFT = {"_": "minus", "|": "backslash", ">": "dot", "{": "bracket_left", "}": "bracket_right",
         "&": "7", "*": "8", "(": "9", ")": "0", "$": "4", "?": "slash", '"': "apostrophe", "!": "1",
         "@": "2", "#": "3", ":": "semicolon", "+": "equal", "<": "comma"}

time.sleep(5)
mon = socket.socket(socket.AF_UNIX)
mon.connect(sock_path)

def cmd(text):
    mon.send((text + "\n").encode())
    time.sleep(0.05)

def typed(text):
    for ch in text:
        if ch in SHIFT: key = "shift-" + SHIFT[ch]
        elif ch in KEYS: key = KEYS[ch]
        elif ch.isupper(): key = "shift-" + ch.lower()
        else: key = ch
        cmd("sendkey " + key)

deadline = time.time() + 600
while time.time() < deadline:
    time.sleep(15)
    shot = out / "console.png"
    cmd(f"screendump {shot} -f png")
    time.sleep(2)
    text = subprocess.run(["tesseract", shot, "-"], capture_output=True, text=True).stdout
    if mode == "tpm" and "passphrase" in text.lower():
        print(text)
        sys.exit("the disk asked for its passphrase: the TPM did not unlock it")
    if luks and "passphrase" in text.lower():
        typed("halogentest\n")
        luks = False
        asked = True
        continue
    if "login:" in text:
        break
else:
    print(text)
    sys.exit("no login prompt appeared")
if mode in ("luks", "luks-stale", "luks-enroll") and not asked:
    sys.exit("the disk was expected to ask for its passphrase, but it did not")

typed("root\n"); time.sleep(3)
typed("halogentest\n"); time.sleep(5)
# The user services start after the fabric clock, which waits about a minute for a GPU
# that a VM does not have. Give them time before reporting.
typed("timeout 180 sh -c 'until journalctl -o cat _SYSTEMD_USER_UNIT=halogen-fetch.service | grep -q halogen-fetch; do sleep 5; done'\n")
time.sleep(5)
typed("{ echo RESULT-START; cat /proc/cmdline; dmesg | grep -i secure; bootctl status | grep -i secure; "
      "bootc status | head -12; udevadm verify /usr/lib/udev/rules.d/70-halogen-devices.rules; "
      "lsblk -f | grep -i crypto; "
      "for d in $(lsblk -rno PATH,FSTYPE | awk '$2==\"crypto_LUKS\"{print $1}'); do cryptsetup luksDump $d | grep -i systemd-tpm2; done; vgs --noheadings -o vg_name; findmnt -rn -o TARGET,SOURCE -t xfs; sestatus | head -3; id halogen; loginctl show-user halogen -p Linger; "
      "systemctl status user@970.service --no-pager | head -4; journalctl --no-pager -n 8 -o cat _SYSTEMD_USER_UNIT=halogen-fetch.service; systemctl --failed --no-legend --no-pager; "
      "systemctl is-active firewalld halogen-prepare; echo RESULT-END; } > /dev/ttyS0 2>&1\n")

def wait_serial(marker, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        time.sleep(5)
        log = serial.read_text(errors="replace")
        if marker in log:
            return log
    sys.exit(f"{marker} never reached the serial log")

log = wait_serial("RESULT-END", 300)
report = log.split("RESULT-START")[-1].split("RESULT-END")[0]
(out / "report.txt").write_text(re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", report))

if mode in ("luks-stale", "luks-enroll"):
    # Exactly what INSTALL.md tells people to run; PASSWORD answers the passphrase prompt.
    # For a stale binding, PCR 7 is first extended so the TPM records a value the next boot
    # won't reproduce, like a BIOS or Secure Boot change after enrolling.
    # pcrextend skips non-UKI boots unless told to measure; then check PCR 7 really moved.
    stale = ("before=$(cat /sys/class/tpm/tpm0/pcr-sha256/7) && "
             "SYSTEMD_FORCE_MEASURE=1 /usr/lib/systemd/systemd-pcrextend --pcr=7 halogen-test-stale && "
             "[ \"$(cat /sys/class/tpm/tpm0/pcr-sha256/7)\" != \"$before\" ] && echo PCR7-CHANGED && "
             if mode == "luks-stale" else "")
    typed("{ " + stale + "PASSWORD=halogentest halogen-enroll-tpm; } "
          "> /dev/ttyS0 2>&1; echo ENROLL-RC=$? > /dev/ttyS0\n")
    log = wait_serial("ENROLL-RC=", 120)
    tail = log.split("RESULT-END")[-1]
    print(tail)
    if mode == "luks-stale" and "PCR7-CHANGED" not in tail:
        sys.exit("PCR 7 could not be changed, so the stale-binding test would prove nothing")
    if "ENROLL-RC=0" not in tail:
        sys.exit("halogen-enroll-tpm failed")
    typed("systemctl poweroff\n")
sys.exit(0)
