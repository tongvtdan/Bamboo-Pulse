#!/usr/bin/env python3
"""Validate this template repository without installing packages."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    "AGENTS.md", "CODEX.md", "CLAUDE.md", "CHAT_NAMING.md", "PROJECT_STATE.md",
    "SHORTCUTS.md", "SPEC.md", "DESIGN.md", "WORKFLOW.md", "README.md",
    "app/AGENTS.md", "docs/delivery/reusable-requests.md",
    "docs/delivery/development-team.md", "examples/trail-log.md",
    "karpathy-guidelines/SKILL.md", "karpathy-guidelines/references/examples.md",
    ".github/PULL_REQUEST_TEMPLATE.md", ".github/ISSUE_TEMPLATE/bug_report.md",
    ".github/ISSUE_TEMPLATE/feature_request.md", ".github/workflows/ci.yml.example",
    ".github/workflows/validate-template.yml", "scripts/validate_template.py",
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
    docs = sorted(p for p in ROOT.rglob("*.md") if ".git" not in p.relative_to(ROOT).parts)
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

    starter = ROOT / ".github/workflows/ci.yml.example"
    workflow = ROOT / "WORKFLOW.md"
    if starter.is_file() and workflow.is_file():
        if "lint-test-build:" not in starter.read_text(encoding="utf-8"):
            errors.append("CI starter: expected lint-test-build job")
        for reference in (".github/workflows/ci.yml.example", ".github/workflows/ci.yml", "lint-test-build"):
            if reference not in workflow.read_text(encoding="utf-8"):
                errors.append(f"WORKFLOW.md: missing CI reference: {reference}")
        readme = ROOT / "README.md"
        if readme.is_file() and ".github/workflows/ci.yml.example" not in readme.read_text(encoding="utf-8"):
            errors.append("README.md: missing CI starter reference")

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"PASS: {len(docs)} Markdown files, {link_count} local links/anchors, required paths, placeholders, and CI references.")
    return 0


if __name__ == "__main__":
    raise SystemExit(validate())
