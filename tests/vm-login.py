"""Log in at a VM console through the QEMU monitor and capture a report on serial."""
import pathlib, re, socket, subprocess, sys, time

sock_path, serial, out = sys.argv[1:4]
luks = len(sys.argv) > 4 and sys.argv[4] == "luks"
serial, out = pathlib.Path(serial), pathlib.Path(out)
KEYS = {" ": "spc", "-": "minus", "=": "equal", ".": "dot", "/": "slash", ";": "semicolon",
        ",": "comma", "'": "apostrophe", "\n": "ret"}
SHIFT = {"_": "minus", "|": "backslash", ">": "dot", "{": "bracket_left", "}": "bracket_right",
         "&": "7", "*": "8", "(": "9", ")": "0"}

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
    if luks and "passphrase" in text.lower():
        typed("halogentest\n")
        luks = False
        continue
    if "login:" in text:
        break
else:
    print(text)
    sys.exit("no login prompt appeared")

typed("root\n"); time.sleep(3)
typed("halogentest\n"); time.sleep(5)
# The user services start after the fabric clock, which waits about a minute for a GPU
# that a VM does not have. Give them time before reporting.
typed("timeout 180 sh -c 'until journalctl -o cat _SYSTEMD_USER_UNIT=halogen-fetch.service | grep -q halogen-fetch; do sleep 5; done'\n")
time.sleep(5)
typed("{ echo RESULT-START; cat /proc/cmdline; dmesg | grep -i secure; bootctl status | grep -i secure; "
      "bootc status | head -12; udevadm verify /usr/lib/udev/rules.d/70-halogen-devices.rules; "
      "lsblk -f | grep -i crypto; vgs --noheadings -o vg_name; findmnt -rn -o TARGET,SOURCE -t xfs; sestatus | head -3; id halogen; loginctl show-user halogen -p Linger; "
      "systemctl status user@970.service --no-pager | head -4; journalctl --no-pager -n 8 -o cat _SYSTEMD_USER_UNIT=halogen-fetch.service; systemctl --failed --no-legend --no-pager; "
      "systemctl is-active firewalld halogen-prepare; echo RESULT-END; } > /dev/ttyS0 2>&1\n")

deadline = time.time() + 300
while time.time() < deadline:
    time.sleep(5)
    log = serial.read_text(errors="replace")
    if "RESULT-END" in log.split("RESULT-START")[-1] and "RESULT-START" in log:
        report = log.split("RESULT-START")[-1].split("RESULT-END")[0]
        (out / "report.txt").write_text(re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", report))
        sys.exit(0)
sys.exit("the report never reached the serial log")
