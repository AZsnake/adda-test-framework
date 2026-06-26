#!/usr/bin/env python3
"""
convert_all_to_utf8.py

Recursively convert text files under a directory to UTF-8 encoding.

Usage:
  python tools/utf8/convert_all_to_utf8.py [path] [--backup] [--dry-run]

Examples:
  python tools/utf8/convert_all_to_utf8.py .           # convert files in current dir
  python tools/utf8/convert_all_to_utf8.py ../src --backup

Notes:
- The script will skip binary files and common VCS/build folders by default.
- If `chardet` is available it will be used for detection; otherwise a small fallback detection is used.
"""

import argparse
import os
import sys
import shutil

try:
    import chardet
except Exception:
    chardet = None

COMMON_SKIP_DIRS = {'.git', '.hg', '.svn', 'build', 'dist', '__pycache__'}

def is_probably_binary(data: bytes) -> bool:
    if not data:
        return False
    if b'\x00' in data:
        return True
    if is_valid_utf8(data):
        return False
    # sample printable range
    text_chars = bytearray(range(32, 127)) + b"\n\r\t\b"
    nontext = 0
    sample = data[:4096]
    for b in sample:
        if b not in text_chars:
            nontext += 1
    return (nontext / max(1, len(sample))) > 0.30


def is_valid_utf8(data: bytes) -> bool:
    try:
        data.decode('utf-8', errors='strict')
        return True
    except UnicodeDecodeError:
        return False


def detect_encoding(data: bytes):
    # Always prefer UTF-8 when the whole file is valid UTF-8. UTF-8 byte
    # sequences can also decode as GBK/GB18030, which would corrupt Chinese text.
    if is_valid_utf8(data):
        return 'utf-8'

    sample = data[:8192]
    if chardet is not None:
        res = chardet.detect(sample)
        encoding = res.get('encoding')
        confidence = res.get('confidence', 0) or 0
        if encoding and confidence >= 0.7:
            return encoding

    candidates = ['utf-8-sig', 'gb18030', 'gbk', 'cp1252', 'iso-8859-1']
    for enc in candidates:
        try:
            data.decode(enc, errors='strict')
            return enc
        except Exception:
            continue
    return None


def convert_file(path, backup=False, dry_run=False):
    with open(path, 'rb') as f:
        data = f.read()
    if is_probably_binary(data):
        return False, 'binary'
    enc = detect_encoding(data)
    if not enc:
        enc = 'unknown'
    normalized_enc = enc.lower() if isinstance(enc, str) else enc
    if normalized_enc and 'utf-8' in normalized_enc:
        return False, 'already-utf8'
    try:
        text = data.decode(enc or 'utf-8', errors='strict')
    except Exception:
        # best-effort fallback
        try:
            text = data.decode('utf-8', errors='replace')
        except Exception:
            text = data.decode('latin-1', errors='replace')
    if dry_run:
        return True, f'will-convert-from-{enc}'
    if backup:
        shutil.copy2(path, path + '.bak')
    # write back as UTF-8 without BOM
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8'))
    return True, f'converted-from-{enc}'


def should_skip_dir(name, extra_skip):
    if name in COMMON_SKIP_DIRS:
        return True
    if name.startswith('.'):
        return True
    if name in extra_skip:
        return True
    return False


def main():
    parser = argparse.ArgumentParser(description='Recursively convert files to UTF-8')
    parser.add_argument('root', nargs='?', default='.', help='Root directory to scan')
    parser.add_argument('--backup', action='store_true', help='Create .bak backup for converted files')
    parser.add_argument('--dry-run', action='store_true', help='Do not modify files; only report')
    parser.add_argument('--skip-dirs', default='', help='Comma-separated extra directories to skip')
    parser.add_argument('--extensions', default='', help='Comma-separated extensions to restrict (e.g. .v,.sv,.py); default = all')
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    extra_skip = set([s for s in args.skip_dirs.split(',') if s.strip()])
    exts = [e.strip().lower() for e in args.extensions.split(',') if e.strip()]

    total = 0
    converted = 0
    skipped = 0
    failures = 0

    for dirpath, dirnames, filenames in os.walk(root):
        # filter out skip dirs in-place
        dirnames[:] = [d for d in dirnames if not should_skip_dir(d, extra_skip)]
        for fn in filenames:
            total += 1
            path = os.path.join(dirpath, fn)
            if exts:
                if not any(fn.lower().endswith(e) for e in exts):
                    skipped += 1
                    continue
            try:
                ok, reason = convert_file(path, backup=args.backup, dry_run=args.dry_run)
                if ok:
                    converted += 1
                    print(f'[OK] {path} -> {reason}')
                else:
                    skipped += 1
                    print(f'[SKIP] {path} -> {reason}')
            except Exception as e:
                failures += 1
                print(f'[ERR] {path} -> {e}')

    print('\nSummary:')
    print(f'  scanned: {total}')
    print(f'  converted: {converted}')
    print(f'  skipped: {skipped}')
    print(f'  failures: {failures}')

    if chardet is None:
        print('\nNote: Optional dependency `chardet` not found. For better detection, run:')
        print('  pip install chardet')


if __name__ == '__main__':
    main()
