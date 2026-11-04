#!/bin/bash
set -euo pipefail
scripts=(scripts/*.sh tests/*.sh files/usr/bin/* files/usr/libexec/halogen/*)
for f in "${scripts[@]}"; do
  bash -n "$f"
  [ -x "$f" ] || { echo "$f is not executable" >&2; exit 1; }
done
if command -v shellcheck >/dev/null; then shellcheck -x "${scripts[@]}"; else echo "shellcheck not installed, skipped"; fi

python3 - <<'P'
import configparser, glob, os, re, tomllib, xml.dom.minidom

kargs = tomllib.load(open("files/usr/lib/bootc/kargs.d/10-halogen.toml", "rb"))["kargs"]
assert "iommu=pt" in kargs and not any(k.startswith("amd_iommu") for k in kargs)
gtt = next(int(k.split("=")[1]) for k in kargs if k.startswith("amdgpu.gttsize="))
pages = next(int(k.split("=")[1]) for k in kargs if k.startswith("ttm.pages_limit="))
assert gtt * 1024 == pages * 4, "GTT and TTM limits disagree"
ks = open("kickstart/strix-halo.ks").read()
assert all(k in ks for k in kargs), "kickstart kernel arguments differ from kargs.d"

class Multi(dict):
    def __setitem__(self, k, v):
        if isinstance(v, list) and k in self: self[k].extend(v)
        else: super().__setitem__(k, v)
units = glob.glob("files/usr/lib/systemd/system/*.service") + glob.glob("files/usr/lib/systemd/user/*.service") \
      + glob.glob("files/usr/lib/systemd/system/*.d/*.conf") + glob.glob("files/etc/containers/systemd/users/970/*")
for path in units:
    c = configparser.RawConfigParser(dict_type=Multi, strict=False, interpolation=None)
    c.optionxform = str
    c.read(path)
    assert c.sections(), path

q = open("files/etc/containers/systemd/users/970/halogen.container").read()
assert "HALOGEN_DOWNLOAD" not in q.replace("# No download settings here", "")
assert "@sha256" not in q and "Image=@HALOGEN_IMAGE@" in q
for lib in ("libxrt_coreutil", "libxrt_core", "libxrt_driver_xdna"):
    assert len(re.findall(rf"^Volume=/usr/lib/halogen/xrt/{lib}\.so\.2:", q, re.M)) == 3, lib
xml.dom.minidom.parse("files/usr/lib/firewalld/services/halogen.xml")
print("static checks ok")
P
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))"
