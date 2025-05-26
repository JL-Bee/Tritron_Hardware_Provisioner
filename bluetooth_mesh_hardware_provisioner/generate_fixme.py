#!/usr/bin/env python3
import os
import re

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.join(ROOT_DIR, 'lib')
FIXME_MD = os.path.join(ROOT_DIR, 'FIXME.md')
TAG_PATTERN = re.compile(r'//\s*(TODO|BUG|HACK|FIXME)\b.*', re.IGNORECASE)
INCLUDE_EXT = {'.c', '.cpp', '.h', '.hpp', '.py', '.js', '.ts', '.dart'}

def extract_comments():
    all_issues = []
    for root, _, files in os.walk(LIB_DIR):
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext not in INCLUDE_EXT:
                continue
            path = os.path.join(root, f)
            rel_path = os.path.relpath(path, ROOT_DIR)
            with open(path, 'r', encoding='utf-8', errors='ignore') as file:
                for i, line in enumerate(file, 1):
                    match = TAG_PATTERN.search(line)
                    if match:
                        all_issues.append((rel_path, i, line.strip()))
    return all_issues

def write_fixme_md(issues):
    with open(FIXME_MD, 'w', encoding='utf-8') as f:
        f.write("# FIXME, TODO, BUG, and HACK List\n\n")
        if not issues:
            f.write("_No outstanding TODOs, BUGs, FIXMEs, or HACKs found._\n")
            return
        last_file = None
        for rel_path, line_no, comment in sorted(issues):
            if last_file != rel_path:
                if last_file is not None:
                    f.write("\n")
                f.write(f"## {rel_path}\n")
                last_file = rel_path
            f.write(f"- Line {line_no}: `{comment}`\n")

if __name__ == "__main__":
    issues = extract_comments()
    write_fixme_md(issues)
    print(f"Wrote {len(issues)} issues to {FIXME_MD}")
