"""Pick the boot menu's unattended entry (the third) through the QEMU monitor.

Usage: grub-pick.py monitor.sock serial.log
The guided install uses answers only from that entry (halos.unattended=1), so the VM test must
choose it within the menu's 5 s countdown. GRUB draws its menu on the serial port too, so this
watches the serial log (instant, unlike reading the screen with OCR, which once took longer than
the countdown), presses Down, Down, Enter, and then checks which entry GRUB says it is booting.
The first key stops the countdown.
"""
import pathlib, re, socket, sys, time

sock_path, serial = sys.argv[1], pathlib.Path(sys.argv[2])
WANT = "unattended test install"
deadline = time.time() + 180

mon = None
while mon is None and time.time() < deadline:
    try:
        mon = socket.socket(socket.AF_UNIX)
        mon.connect(sock_path)
    except OSError:
        mon = None
        time.sleep(0.5)
if mon is None:
    sys.exit("the QEMU monitor never appeared")

def log():
    # Escape sequences become line breaks: GRUB positions each menu line with one.
    try:
        return re.sub(r"\x1b\[[0-9;=?]*[A-Za-z]", "\n", serial.read_text(errors="replace"))
    except FileNotFoundError:
        return ""

while time.time() < deadline:
    if "executed automatically" in log():
        break
    time.sleep(0.1)
else:
    sys.exit("the boot menu never appeared on the serial port")
for key in ("down", "down", "ret"):
    mon.send(f"sendkey {key}\n".encode())
    time.sleep(0.15)

# Which entry ran: GRUB prints "Booting `<entry>'" only when its countdown ran out (then it is the
# default entry, which waits for typed answers), and marks the highlighted entry with "*".
# Decide once the kernel has started printing, so the install's 25-minute timeout never has to.
deadline = time.time() + 60
while time.time() < deadline:
    text = log()
    menu_end = text.rfind("executed automatically")
    after = text[menu_end:]
    booting = re.search(r"Booting `([^']*)'", after)
    if booting:
        if WANT in booting.group(1):
            print(f"picked: {booting.group(1)}")
            sys.exit(0)
        sys.exit(f"GRUB's countdown ran out and it booted '{booting.group(1)}', not the unattended entry")
    if re.search(r"\bOK\b|Linux version|Expecting device", after):
        chosen = re.findall(r"\*(Install halOS[^\n]*?)\s*$", text, re.M)
        if chosen and WANT in chosen[-1]:
            print(f"picked: {chosen[-1].strip()}")
            sys.exit(0)
        sys.exit(f"GRUB booted '{chosen[-1].strip() if chosen else 'an unknown entry'}', not the unattended entry")
    time.sleep(0.2)
sys.exit("GRUB never started the chosen entry")
