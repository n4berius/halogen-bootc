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

kargs = tomllib.load(open("variants/npu/usr/lib/bootc/kargs.d/10-halogen.toml", "rb"))["kargs"]
no_npu = tomllib.load(open("variants/no-npu/usr/lib/bootc/kargs.d/10-halogen.toml", "rb"))["kargs"]
assert "amd_iommu=off" in no_npu and [k for k in kargs if "=" in k and "iommu" not in k] == [k for k in no_npu if "iommu" not in k]
assert "iommu=pt" in kargs and not any(k.startswith("amd_iommu") for k in kargs)
gtt = next(int(k.split("=")[1]) for k in kargs if k.startswith("amdgpu.gttsize="))
pages = next(int(k.split("=")[1]) for k in kargs if k.startswith("ttm.pages_limit="))
assert gtt * 1024 == pages * 4, "GTT and TTM limits disagree"

class Multi(dict):
    def __setitem__(self, k, v):
        if isinstance(v, list) and k in self: self[k].extend(v)
        else: super().__setitem__(k, v)
units = glob.glob("variants/npu/usr/lib/systemd/system/*.d/*.conf") + glob.glob("variants/npu/etc/containers/systemd/users/970/*.d/*") + glob.glob("files/usr/lib/systemd/system/*.service") + glob.glob("files/usr/lib/systemd/user/*.service") \
      + glob.glob("files/usr/lib/systemd/system/*.d/*.conf") + glob.glob("files/etc/containers/systemd/users/970/*")
for path in units:
    c = configparser.RawConfigParser(dict_type=Multi, strict=False, interpolation=None)
    c.optionxform = str
    c.read(path)
    assert c.sections(), path

q = open("files/etc/containers/systemd/users/970/halogen.container").read()
n = open("variants/npu/etc/containers/systemd/users/970/halogen.container.d/10-npu.conf").read()
assert "accel" not in q and "/usr/lib/halogen/xrt" not in q
locked = {l.split("=")[0] for l in open("files/usr/share/halogen/locked.env") if l.startswith("HALOGEN_")}
for edition in ("npu", "no-npu"):
    allowed = set(open(f"variants/{edition}/usr/share/halogen/options.allowed").read().split())
    assert allowed and not allowed & locked, allowed & locked
    assert "HALOGEN_DOWNLOAD" not in allowed
    assert (edition == "npu") == ("HALOGEN_NPU_MODELS" in allowed)
assert "HALOGEN_DOWNLOAD" not in q.replace("# No download settings here", "")
assert "@sha256" not in q and "Image=@HALOGEN_IMAGE@" in q
for lib in ("libxrt_coreutil", "libxrt_core", "libxrt_driver_xdna"):
    assert len(re.findall(rf"^Volume=/usr/lib/halogen/xrt/{lib}\.so\.2:", n, re.M)) == 3, lib
xml.dom.minidom.parse("files/usr/lib/firewalld/services/halogen.xml")
pins = dict(l.strip().split("=", 1) for l in open("versions.env") if "=" in l and not l.startswith("#"))
assert re.fullmatch(r"[0-9a-f]{40}", pins["HALOGEN_WEIGHTS_REVISION"]), "HALOGEN_WEIGHTS_REVISION must be a commit, not a branch"
print("static checks ok")
P
python3 -c "import glob, yaml; [yaml.safe_load(open(f)) for f in glob.glob('.github/**/*.yml', recursive=True)]"
