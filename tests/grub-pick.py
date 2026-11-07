"""Pick the boot menu's unattended entry (the third) through the QEMU monitor.

Usage: grub-pick.py monitor.sock out-dir
The guided install uses answers only from that entry (halos.unattended=1), so the VM test must
choose it within the menu's 5 s countdown: watch the screen, then press Down, Down, Enter. The
first key stops the countdown.
"""
import pathlib, socket, subprocess, sys, time

sock_path, out = sys.argv[1], pathlib.Path(sys.argv[2])
deadline = time.time() + 180
mon = None
while mon is None and time.time() < deadline:
    try:
        mon = socket.socket(socket.AF_UNIX)
        mon.connect(sock_path)
    except OSError:
        mon = None
        time.sleep(1)
if mon is None:
    sys.exit("the QEMU monitor never appeared")

def cmd(text):
    mon.send((text + "\n").encode())
    time.sleep(0.2)

text = ""
while time.time() < deadline:
    shot = out / "grub.png"
    cmd(f"screendump {shot} -f png")
    time.sleep(0.5)
    text = subprocess.run(["tesseract", shot, "-"], capture_output=True, text=True).stdout
    if "unattended" in text.lower():
        for key in ("down", "down", "ret"):
            cmd("sendkey " + key)
        print("picked the unattended entry")
        sys.exit(0)
print(text)
sys.exit("the boot menu's unattended entry never appeared")
