#!/usr/bin/env python3
"""Verificação adicional de privacidade. Não substitui um scanner de segredos nem revisão humana."""
import argparse
import json
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PROHIBITED_PARTS = {".build", ".claude", ".codex", ".aws", ".security-audit", "xcuserdata"}
PROHIBITED_NAMES = {"auth.json", "credentials.json", "state.json"}
EXAMPLE_DOMAINS = {"example.com", "example.org", "example.test", "users.noreply.github.com"}
HOME_PATH = re.compile(r"/Users/([\w.-]+)")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
KEY_HEADER = re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")
CREDENTIAL_URL = re.compile(r"https?://[^\s/:]+:[^\s/@]+@")


def candidate_files():
    output = subprocess.check_output(["git", "ls-files", "-c", "-o", "--exclude-standard", "-z"], cwd=ROOT)
    return sorted(set(name for name in output.decode().split("\0") if name))


def inspect_png(path):
    data = path.read_bytes()
    offset = 8
    while offset + 12 <= len(data):
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        if kind in {b"tEXt", b"zTXt", b"iTXt", b"eXIf"}:
            return True
        offset += size + 12
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", type=Path, help="Copia somente os arquivos revisados para uma pasta nova, sem .git.")
    parser.add_argument("--history", action="store_true", help="Bloqueia também e-mails pessoais nos metadados dos commits.")
    args = parser.parse_args()
    files = candidate_files()
    findings = []
    for name in files:
        path = ROOT / name
        relative = Path(name)
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_symlink():
            findings.append({"file": name, "rule": "symlink"})
            continue
        if (set(relative.parts) & PROHIBITED_PARTS or relative.name in PROHIBITED_NAMES
                or relative.name.startswith(".env") and relative.name != ".env.example"
                or relative.suffix.lower() in {".pem", ".key", ".p12", ".pfx", ".log", ".zip"}
                or ".bak-" in relative.name):
            findings.append({"file": name, "rule": "private_or_generated_file"})
        if path.suffix.lower() == ".png" and inspect_png(path):
            findings.append({"file": name, "rule": "image_metadata"})
        try:
            text = path.read_text()
        except UnicodeError:
            continue
        for match in HOME_PATH.finditer(text):
            if match.group(1) not in {"usuario", "user", "example", "test", "runner"}:
                findings.append({"file": name, "rule": "personal_home_path", "line": text.count("\n", 0, match.start()) + 1})
        for match in EMAIL.finditer(text):
            if match.group(1).lower() not in EXAMPLE_DOMAINS and match.group(0).lower() != "noreply@github.com":
                findings.append({"file": name, "rule": "non_example_email", "line": text.count("\n", 0, match.start()) + 1})
        for rule, pattern in [("private_key", KEY_HEADER), ("credential_url", CREDENTIAL_URL)]:
            if pattern.search(text):
                findings.append({"file": name, "rule": rule})
    if args.history:
        approved = set()
        policy_path = ROOT / ".publication-policy.json"
        if policy_path.exists():
            try:
                policy = json.loads(policy_path.read_text())
                boundary = policy["legacy_author_metadata"]["through_commit"]
                entries = policy["legacy_author_metadata"]["approved_commit_ids"]
                if not re.fullmatch(r"[a-f0-9]{40}", boundary) or not isinstance(entries, list):
                    raise ValueError("Invalid boundary")
                if any(not isinstance(entry, str) or not re.fullmatch(r"[a-f0-9]{40}", entry) for entry in entries):
                    raise ValueError("Invalid commit id")
                ancestors = set(subprocess.check_output(["git", "rev-list", boundary], cwd=ROOT,
                                                        stderr=subprocess.DEVNULL).decode().splitlines())
                approved = set(entries)
                if not approved.issubset(ancestors):
                    raise ValueError("Exception exceeds approved history")
            except (ValueError, KeyError, TypeError, subprocess.CalledProcessError):
                findings.append({"rule": "invalid_publication_policy"})
                approved = set()
        history = subprocess.check_output(["git", "log", "--all", "--format=%H%x00%ae%x00%ce"], cwd=ROOT).decode()
        affected = set()
        for record in history.splitlines():
            fields = record.split("\0")
            if len(fields) != 3:
                continue
            for email in fields[1:]:
                value = email.lower()
                if value and not (value.endswith("@users.noreply.github.com") or value == "noreply@github.com"):
                    if fields[0] not in approved:
                        affected.add(fields[0])
        if affected:
            findings.append({"rule": "personal_commit_email", "affected_commits": len(affected),
                             "example_commits": sorted(affected)[:3]})
    print(json.dumps({"files_checked": len(files), "findings": findings}, ensure_ascii=False, indent=2))
    if findings:
        return 1
    if args.export:
        import shutil
        destination = args.export.resolve()
        if destination.exists():
            parser.error("A pasta de exportação deve ser nova para evitar misturar arquivos não revisados.")
        destination.mkdir(parents=True, mode=0o700)
        copied = 0
        for name in files:
            source = ROOT / name
            if source.is_file():
                target = destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                copied += 1
        print(f"Exportados {copied} arquivos revisados, sem metadados ou histórico Git.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
