#!/usr/bin/env python3
"""Install only the Godot export templates a build needs.

The official templates archive is ~1.3 GB (every platform); a zip can be read
in pieces, so this reads just the named entries over HTTP range requests and
puts them where Godot looks for them.

  tools/export/fetch_templates.py 4.7.2 linux_release.x86_64 linux_debug.x86_64
"""
import io
import os
import sys
import urllib.request
import zipfile


class HttpFile(io.RawIOBase):
    """A read-only, seekable view of a remote file (HTTP Range requests)."""

    def __init__(self, url):
        self.url = url
        self.pos = 0
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as r:
            self.size = int(r.headers["Content-Length"])
            self.url = r.url  # after redirects

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def readinto(self, buf):
        n = min(len(buf), self.size - self.pos)
        if n <= 0:
            return 0
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + n - 1}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        buf[: len(data)] = data
        self.pos += len(data)
        return len(data)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    version, names = sys.argv[1], sys.argv[2:]
    url = f"https://github.com/godotengine/godot/releases/download/{version}-stable/Godot_v{version}-stable_export_templates.tpz"
    dest = os.path.expanduser(f"~/.local/share/godot/export_templates/{version}.stable")
    os.makedirs(dest, exist_ok=True)
    # Big reads: the archive's directory, then each template in one go.
    remote = io.BufferedReader(HttpFile(url), buffer_size=8 << 20)
    with zipfile.ZipFile(remote) as z:
        for name in names + ["version.txt"]:
            out = os.path.join(dest, name)
            with z.open("templates/" + name) as src, open(out, "wb") as dst:
                while chunk := src.read(8 << 20):
                    dst.write(chunk)
            os.chmod(out, 0o755)
            print(f"{name}: {os.path.getsize(out) // 1024} KB")
    print(f"installed in {dest}")


if __name__ == "__main__":
    main()
