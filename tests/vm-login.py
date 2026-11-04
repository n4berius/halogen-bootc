"""Log in at a VM console through the QEMU monitor and capture a report on serial."""
import pathlib, socket, subprocess, sys, time

sock_path, serial, out = sys.argv[1:4]
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
    if "login:" in text:
        break
else:
    print(text)
    sys.exit("no login prompt appeared")

typed("root\n"); time.sleep(3)
typed("halogentest\n"); time.sleep(5)
typed("{ echo RESULT-START; cat /proc/cmdline; dmesg | grep -i secure; bootctl status | grep -i secure; "
      "bootc status | head -12; id halogen; systemctl --failed --no-legend --no-pager; "
      "systemctl is-active firewalld halogen-prepare; echo RESULT-END; } > /dev/ttyS0 2>&1\n")

deadline = time.time() + 120
while time.time() < deadline:
    time.sleep(5)
    log = serial.read_text(errors="replace")
    if "RESULT-END" in log.split("RESULT-START")[-1] and "RESULT-START" in log:
        (out / "report.txt").write_text(log.split("RESULT-START")[-1].split("RESULT-END")[0])
        sys.exit(0)
sys.exit("the report never reached the serial log")
