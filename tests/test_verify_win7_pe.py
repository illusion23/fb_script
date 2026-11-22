"""Unit tests for scripts/verify_win7_pe.py PE32+ compatibility auditing."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import verify_win7_pe as verifier  # noqa: E402


def _build_minimal_pe64(
    *,
    subsystem_major: int = 6,
    subsystem_minor: int = 1,
    imports: dict[str, list[str]] | None = None,
) -> bytes:
    """Build a valid minimal PE32+ (x64) binary with an .idata import table."""
    imports = imports or {"KERNEL32.dll": ["GetLastError", "CreateFileW"]}

    # Layout:
    # 0x000: DOS header (0x40 bytes, e_lfanew = 0x40)
    # 0x040: PE sig (4) + COFF (20) + OptionalHeader64 (240) + 1 SectionHeader (40) = 304 bytes
    # 0x200: .idata section (RVA 0x1000)
    dos_header = bytearray(0x40)
    dos_header[0:2] = b"MZ"
    struct.pack_into("<I", dos_header, 0x3C, 0x40)

    section_rva = 0x1000
    section_raw_ptr = 0x200

    # Build .idata contents
    num_dlls = len(imports)
    desc_table_size = (num_dlls + 1) * 20
    idata = bytearray(desc_table_size)

    def append_aligned(blob: bytes, align: int = 8) -> int:
        pad = (-len(idata)) % align
        idata.extend(b"\x00" * pad)
        rva = section_rva + len(idata)
        idata.extend(blob)
        return rva

    for idx, (dll_name, funcs) in enumerate(imports.items()):
        dll_name_rva = append_aligned(dll_name.encode("ascii") + b"\x00", align=2)
        func_name_rvas: list[int] = []
        for fn in funcs:
            entry = struct.pack("<H", 0) + fn.encode("ascii") + b"\x00"
            func_name_rvas.append(append_aligned(entry, align=2))
        thunk_blob = b"".join(struct.pack("<Q", rva) for rva in func_name_rvas) + struct.pack("<Q", 0)
        oft_rva = append_aligned(thunk_blob, align=8)
        struct.pack_into("<IIIII", idata, idx * 20, oft_rva, 0, 0, dll_name_rva, oft_rva)

    pe_sig = b"PE\x00\x00"
    coff = struct.pack("<HHIIIHH", 0x8664, 1, 0, 0, 0, 240, 0x0022)

    opt = bytearray(240)
    struct.pack_into("<H", opt, 0, 0x20B)  # PE32+
    struct.pack_into("<HH", opt, 40, subsystem_major, subsystem_minor)  # OS version
    struct.pack_into("<HH", opt, 48, subsystem_major, subsystem_minor)  # Subsystem version
    struct.pack_into("<I", opt, 108, 16)  # NumberOfRvaAndSizes
    # DataDirectory[1] = Import Directory
    struct.pack_into("<II", opt, 112 + 8, section_rva, desc_table_size)

    sec = bytearray(40)
    sec[0:8] = b".idata\x00\x00"
    struct.pack_into("<IIII", sec, 8, len(idata), section_rva, len(idata), section_raw_ptr)

    headers = bytes(dos_header) + pe_sig + coff + bytes(opt) + bytes(sec)
    assert len(headers) <= section_raw_ptr
    return headers.ljust(section_raw_ptr, b"\x00") + bytes(idata)


def _populate_release_dir(release_dir: Path, exe_bytes: bytes, dll_bytes: bytes) -> None:
    (release_dir / "data" / "flutter_assets").mkdir(parents=True)
    (release_dir / "data" / "icudtl.dat").write_bytes(b"icu")
    (release_dir / "data" / "app.so").write_bytes(b"aot")
    (release_dir / "fb_group_poster.exe").write_bytes(exe_bytes)
    (release_dir / "flutter_windows.dll").write_bytes(dll_bytes)
    (release_dir / "vcruntime140.dll").write_bytes(b"vc")
    (release_dir / "msvcp140.dll").write_bytes(b"msvcp")
    (release_dir / "ucrtbase.dll").write_bytes(b"ucrt")
    (release_dir / "api-ms-win-crt-runtime-l1-1-0.dll").write_bytes(b"crt")


def test_valid_win7_bundle_passes(tmp_path: Path) -> None:
    pe = _build_minimal_pe64(
        subsystem_major=6,
        subsystem_minor=1,
        imports={"KERNEL32.dll": ["CreateFileW", "LoadLibraryA", "GetProcAddress"]},
    )
    _populate_release_dir(tmp_path, pe, pe)
    assert verifier.verify_bundle(tmp_path) == []


def test_rejects_win10_subsystem_version(tmp_path: Path) -> None:
    bad_pe = _build_minimal_pe64(subsystem_major=10, subsystem_minor=0)
    good_pe = _build_minimal_pe64(subsystem_major=6, subsystem_minor=1)
    _populate_release_dir(tmp_path, bad_pe, good_pe)
    errors = verifier.verify_bundle(tmp_path)
    assert any("subsystem version 10.0 > 6.1" in e for e in errors)


def test_rejects_win10_only_static_api_import(tmp_path: Path) -> None:
    bad_pe = _build_minimal_pe64(
        subsystem_major=6,
        subsystem_minor=1,
        imports={"USER32.dll": ["GetDpiForWindow"], "KERNEL32.dll": ["SetThreadDescription"]},
    )
    good_pe = _build_minimal_pe64(subsystem_major=6, subsystem_minor=1)
    _populate_release_dir(tmp_path, good_pe, bad_pe)
    errors = verifier.verify_bundle(tmp_path)
    assert any("GetDpiForWindow" in e for e in errors)
    assert any("SetThreadDescription" in e for e in errors)


def test_rejects_missing_ucrt_api_sets(tmp_path: Path) -> None:
    pe = _build_minimal_pe64(subsystem_major=6, subsystem_minor=1)
    _populate_release_dir(tmp_path, pe, pe)
    (tmp_path / "api-ms-win-crt-runtime-l1-1-0.dll").unlink()
    errors = verifier.verify_bundle(tmp_path)
    assert any("api-ms-win-crt-" in e for e in errors)
