from __future__ import annotations

import re
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path


TYPE_RE = re.compile(r"Unix file attributes \((\d+) octal\)")


def metadata_type(unzip: str, archive: Path, member: str) -> int:
    result = subprocess.run(
        [unzip, "-Z", "-v", str(archive), member],
        check=True,
        capture_output=True,
        text=True,
    )
    match = TYPE_RE.search(result.stdout)
    if match is None:
        return 0
    return int(match.group(1), 8) // 4096


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="rc-api-archive-") as temp:
        archive = Path(temp) / "malicious.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("Songs/6037/info.dat", b"safe")

            link = zipfile.ZipInfo("Songs/6037/link")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            output.writestr(link, b"../../outside")

            device = zipfile.ZipInfo("Songs/6037/device")
            device.create_system = 3
            device.external_attr = (stat.S_IFCHR | 0o666) << 16
            output.writestr(device, b"")

        assert metadata_type("unzip", archive, "Songs/6037/info.dat") in (0, 8)
        assert metadata_type("unzip", archive, "Songs/6037/link") == 10
        assert metadata_type("unzip", archive, "Songs/6037/device") in (2, 6)
        print("archive extraction integration ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
