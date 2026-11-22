#!/usr/bin/env python3
"""Verify a built Flutter Windows x64 Release bundle for Windows 7 SP1 / 10 / 11 compatibility.

Uses only the Python standard library (zero external dependencies) to inspect PE32+
headers and static import tables of the executable, Flutter engine DLL, and plugins.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

PE_MACHINE_AMD64 = 0x8664
PE32_PLUS_MAGIC = 0x20B

# Static DLL imports that do NOT exist on Windows 7 SP1.
FORBIDDEN_WIN8_PLUS_DLLS = {
    "shcore.dll",
    "dcomp.dll",
    "api-ms-win-core-path-l1-1-0.dll",
    "api-ms-win-core-synch-l1-2-0.dll",
    "api-ms-win-shcore-scaling-l1-1-1.dll",
    "api-ms-win-core-winrt-l1-1-0.dll",
    "api-ms-win-core-winrt-string-l1-1-0.dll",
    "api-ms-win-core-winrt-error-l1-1-0.dll",
}

# Static function imports absent from Windows 7 SP1 system DLLs.
# (Dynamic resolution via LoadLibrary + GetProcAddress is fine and does not appear here.)
FORBIDDEN_WIN8_PLUS_FUNCS = {
    "GetDpiForWindow",
    "GetDpiForSystem",
    "GetDpiForMonitor",
    "SetProcessDpiAwareness",
    "SetProcessDpiAwarenessContext",
    "EnableNonClientDpiScaling",
    "SetThreadDescription",
    "GetThreadDescription",
    "PathCchCanonicalizeEx",
    "PathCchCombineEx",
    "GetHostNameW",
    "GetSystemTimePreciseAsFileTime",
    "DiscardVirtualMemory",
    "OfferVirtualMemory",
    "CreateFile2",
    "WaitOnAddress",
    "WakeByAddressSingle",
    "WakeByAddressAll",
    "RoInitialize",
    "RoUninitialize",
    "RoGetActivationFactory",
}


def _rva_to_offset(rva: int, sections: list[tuple[int, int, int, int]]) -> int | None:
    for vaddr, vsize, raw_size, raw_ptr in sections:
        span = max(vsize, raw_size)
        if vaddr <= rva < vaddr + span:
            return raw_ptr + (rva - vaddr)
    return None


def _read_cstr(data: bytes, offset: int) -> str:
    end = data.find(b"\x00", offset)
    if end == -1:
        end = len(data)
    return data[offset:end].decode("ascii", errors="replace")


def parse_pe(path: Path) -> dict:
    """Parse key PE32+ metadata and static imports from a Windows .exe or .dll."""
    data = path.read_bytes()
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError(f"{path.name}: Not a valid MZ/PE binary")

    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_offset : pe_offset + 4] != b"PE\x00\x00":
        raise ValueError(f"{path.name}: Missing PE signature")

    coff_offset = pe_offset + 4
    machine, num_sections, _, _, _, opt_header_size, _ = struct.unpack_from(
        "<HHIIIHH", data, coff_offset
    )

    opt_offset = coff_offset + 20
    magic = struct.unpack_from("<H", data, opt_offset)[0]
    if magic != PE32_PLUS_MAGIC:
        raise ValueError(
            f"{path.name}: Expected PE32+ (64-bit, magic 0x20B), got 0x{magic:X}"
        )

    major_os, minor_os = struct.unpack_from("<HH", data, opt_offset + 40)
    major_sub, minor_sub = struct.unpack_from("<HH", data, opt_offset + 48)
    num_rva_and_sizes = struct.unpack_from("<I", data, opt_offset + 108)[0]

    import_dir_rva = 0
    import_dir_size = 0
    if num_rva_and_sizes >= 2:
        import_dir_rva, import_dir_size = struct.unpack_from(
            "<II", data, opt_offset + 112 + 8
        )

    sections: list[tuple[int, int, int, int]] = []
    sec_offset = opt_offset + opt_header_size
    for i in range(num_sections):
        entry = sec_offset + i * 40
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, entry + 8)
        sections.append((vaddr, vsize, raw_size, raw_ptr))

    imports: dict[str, list[str]] = {}
    if import_dir_rva and import_dir_size:
        desc_offset = _rva_to_offset(import_dir_rva, sections)
        if desc_offset is not None:
            while desc_offset + 20 <= len(data):
                orig_first_thunk, _, _, name_rva, first_thunk = struct.unpack_from(
                    "<IIIII", data, desc_offset
                )
                if orig_first_thunk == 0 and name_rva == 0 and first_thunk == 0:
                    break
                name_off = _rva_to_offset(name_rva, sections)
                dll_name = (
                    _read_cstr(data, name_off) if name_off is not None else "<unknown>"
                )
                funcs: list[str] = []
                thunk_rva = orig_first_thunk or first_thunk
                thunk_off = _rva_to_offset(thunk_rva, sections)
                if thunk_off is not None:
                    while thunk_off + 8 <= len(data):
                        thunk_val = struct.unpack_from("<Q", data, thunk_off)[0]
                        if thunk_val == 0:
                            break
                        if (thunk_val & (1 << 63)) == 0:
                            hint_name_off = _rva_to_offset(
                                thunk_val & 0xFFFFFFFF, sections
                            )
                            if hint_name_off is not None:
                                funcs.append(_read_cstr(data, hint_name_off + 2))
                        thunk_off += 8
                imports[dll_name.lower()] = funcs
                desc_offset += 20

    return {
        "file": path.name,
        "machine": machine,
        "os_version": (major_os, minor_os),
        "subsystem_version": (major_sub, minor_sub),
        "imports": imports,
    }


def verify_bundle(release_dir: Path) -> list[str]:
    """Return a list of compatibility errors found in the Windows release bundle."""
    errors: list[str] = []

    required_paths = [
        "fb_group_poster.exe",
        "flutter_windows.dll",
        "data/icudtl.dat",
        "data/app.so",
        "data/flutter_assets",
        "vcruntime140.dll",
        "msvcp140.dll",
        "ucrtbase.dll",
    ]
    for rel in required_paths:
        if not (release_dir / rel).exists():
            errors.append(f"Missing required bundle item: {rel}")

    crt_api_sets = list(release_dir.glob("api-ms-win-crt-*.dll"))
    if not crt_api_sets:
        errors.append(
            "Missing app-local Universal C Runtime forwarder DLLs (api-ms-win-crt-*.dll) "
            "needed for out-of-the-box Windows 7 SP1 execution."
        )

    # Inspect app executable, Flutter engine DLL, and any compiled plugin DLLs
    # (skip Microsoft's own VC++/UCRT redistributable DLLs).
    target_binaries = [
        p
        for p in sorted(release_dir.iterdir())
        if p.is_file()
        and p.suffix.lower() in {".exe", ".dll"}
        and not p.name.lower().startswith(
            ("api-ms-win-", "ucrtbase", "vcruntime", "msvcp", "concrt", "vccorlib")
        )
    ]

    for binary in target_binaries:
        try:
            info = parse_pe(binary)
        except ValueError as exc:
            errors.append(str(exc))
            continue

        if info["machine"] != PE_MACHINE_AMD64:
            errors.append(
                f"{binary.name}: Unexpected PE machine 0x{info['machine']:X} (expected x64 0x8664)"
            )

        sub_ver = info["subsystem_version"]
        if sub_ver > (6, 1):
            errors.append(
                f"{binary.name}: PE subsystem version {sub_ver[0]}.{sub_ver[1]} > 6.1 (Windows 7). "
                "Binary will not launch on Windows 7."
            )

        for dll_name, funcs in info["imports"].items():
            if dll_name in FORBIDDEN_WIN8_PLUS_DLLS or dll_name.startswith("ext-ms-win-"):
                errors.append(
                    f"{binary.name}: Static import of Windows 8/10+ DLL '{dll_name}'"
                )
            for fn in funcs:
                if fn in FORBIDDEN_WIN8_PLUS_FUNCS:
                    errors.append(
                        f"{binary.name}: Static import of Windows 8/10+ API '{fn}' from '{dll_name}'"
                    )

        print(
            f"[OK] {binary.name}: x64, subsystem {sub_ver[0]}.{sub_ver[1]}, "
            f"{len(info['imports'])} imported DLL(s)"
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify Flutter Windows Release bundle for Windows 7 SP1 / 10 / 11 compatibility."
    )
    parser.add_argument(
        "release_dir",
        type=Path,
        help="Path to Flutter Windows Release output directory (e.g. mobile_app/build/windows/x64/runner/Release)",
    )
    args = parser.parse_args()

    if not args.release_dir.is_dir():
        print(f"[ERROR] Release directory not found: {args.release_dir}", file=sys.stderr)
        return 2

    errors = verify_bundle(args.release_dir)
    if errors:
        print("\n[FAIL] Windows 7 / 10 / 11 compatibility check failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("\n[PASS] Windows 7 SP1 x64, Windows 10, and Windows 11 PE compatibility verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
