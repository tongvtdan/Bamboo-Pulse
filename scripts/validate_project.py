#!/usr/bin/env python3
"""Validate Bamboo Pulse contributor documentation without installing packages."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    "AGENTS.md", "CODEX.md", "CLAUDE.md", "CHAT_NAMING.md", "PROJECT_STATE.md",
    "SHORTCUTS.md", "SPEC.md", "DESIGN.md", "WORKFLOW.md", "README.md",
    "Sources/AGENTS.md", "docs/delivery/reusable-requests.md",
    "docs/delivery/development-team.md", "examples/preview.md",
    "karpathy-guidelines/SKILL.md", "karpathy-guidelines/references/examples.md",
    ".github/PULL_REQUEST_TEMPLATE.md", ".github/ISSUE_TEMPLATE/bug_report.md",
    ".github/ISSUE_TEMPLATE/feature_request.md", ".github/workflows/ci.yml",
    ".github/workflows/validate-project.yml", "scripts/validate_project.py", "Package.swift", "BambooPulse.xcodeproj/project.pbxproj", "LICENSE",
    "Runtime/pulse-runtime/package.py", "Runtime/pulse-runtime/build-review-dmg.sh",
    "Runtime/status-service/codex-desktop-wrapper", "script/build_and_run.sh",
)
LINK = re.compile(r"!?\[[^\]]*\]\((<[^>]+>|[^\s)]+)(?:\s+[\"'][^\n]*?[\"'])?\)")
PLACEHOLDER = re.compile(r"<[^<>\n]+>")


def prose(text):
    text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S)
    lines = []
    fence = None
    for line in text.splitlines():
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return "\n".join(lines), fence


def slug(heading):
    return re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")


def anchors(text):
    body, _ = prose(text)
    seen = {}
    result = set()
    for heading in re.findall(r"^#{1,6}\s+(.+?)(?:\s+#+)?$", body, re.M):
        base = slug(heading)
        count = seen.get(base, 0)
        result.add(base if count == 0 else f"{base}-{count}")
        seen[base] = count + 1
    return result


def validate():
    errors = [f"missing required path: {name}" for name in REQUIRED if not (ROOT / name).is_file()]
    docs = sorted(p for p in ROOT.rglob("*.md") if not {".git", ".build", "DerivedData", "dist", ".swiftpm"}.intersection(p.relative_to(ROOT).parts))
    link_count = 0
    for path in docs:
        relative = path.relative_to(ROOT)
        text = path.read_text(encoding="utf-8")
        body, open_fence = prose(text)
        if open_fence:
            errors.append(f"{relative}: unclosed fenced block")
        for number, line in enumerate(text.splitlines(), 1):
            if line.rstrip() != line:
                errors.append(f"{relative}:{number}: trailing whitespace")
        for target in LINK.findall(body):
            target = target.removeprefix("<").removesuffix(">")
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("//"):
                continue
            # Link placeholders are intentional until the generated project is configured.
            if PLACEHOLDER.search(target):
                continue
            location, _, fragment = target.partition("#")
            location = unquote(location.split("?", 1)[0])
            destination = (path.parent / location).resolve() if location else path
            link_count += 1
            if not destination.is_relative_to(ROOT):
                errors.append(f"{relative}: local link leaves the repository: {target}")
            elif not destination.exists():
                errors.append(f"{relative}: missing local link target: {target}")
            elif fragment and destination.suffix == ".md":
                if unquote(fragment) not in anchors(destination.read_text(encoding="utf-8")):
                    errors.append(f"{relative}: missing heading anchor: {target}")
        unquoted = re.sub(r"`+[^`]*`+", "", body)
        if PLACEHOLDER.search(unquoted):
            errors.append(f"{relative}: wrap prose placeholders in code spans so Markdown preserves them")

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"PASS: {len(docs)} Markdown files, {link_count} local links/anchors, required paths, and Markdown formatting.")
    return 0


if __name__ == "__main__":
    raise SystemExit(validate())
