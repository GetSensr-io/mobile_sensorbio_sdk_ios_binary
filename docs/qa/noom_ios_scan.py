#!/usr/bin/env python3
"""Local copy and security scan for the Noom iOS white-label NoomApp.

The scanner is deterministic and secret-safe: it reports paths, line numbers, terms,
and classification only. It never prints matched source lines or secret values.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable

FORBIDDEN_TERMS = [
    "SensorBio",
    "Sensor Bio",
    "Noom App",
    "SDK demo",
    "SB_",
    "\u2014",
    "\u2013",
    "Bearer",
    "BRANDFETCH_API_KEY",
]

ALLOWED_TERMS = [
    "Noom Band",
    "GLP-1",
    "Weight Care",
    "Sleep",
    "Recovery",
    "Coach",
]

TEXT_SUFFIXES = {
    ".swift",
    ".plist",
    ".md",
    ".html",
    ".json",
    ".svg",
    ".txt",
    ".strings",
}

DEFAULT_SCAN_ROOTS = [
    "NoomApp/NoomApp",
    "docs/mockups/noom-mobile-mockups",
]

EXCLUDED_DIRS = {
    ".git",
    ".build",
    "build",
    "DerivedData",
    "Pods",
    "node_modules",
    "screenshots",
    "assets/fonts",
}

VISIBLE_DOC_ROOT_MARKERS = (
    "docs/mockups/noom-mobile-mockups",
)

VISIBLE_ASSET_SUFFIXES = {".md", ".html", ".json", ".svg", ".strings"}
SECURITY_TERMS = {"Bearer", "BRANDFETCH_API_KEY"}
DASH_TERMS = {"\u2014", "\u2013"}

STRING_LITERAL_RE = re.compile(r'"(?:[^"\\]|\\.)*"')


@dataclass(frozen=True)
class Hit:
    term: str
    path: str
    line: int
    classification: str
    reason: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan Noom iOS app source and mockup assets for forbidden copy and security terms."
    )
    parser.add_argument(
        "--repo-root",
        default=Path(__file__).resolve().parents[2],
        type=Path,
        help="Repository root. Defaults to two directories above this script.",
    )
    parser.add_argument(
        "--root",
        action="append",
        dest="roots",
        help="Relative root to scan. May be repeated. Defaults to app source and Noom mockups.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON instead of human-readable text.",
    )
    parser.add_argument(
        "--strict-internal",
        action="store_true",
        help="Treat internal implementation hits as failures. Default only fails visible/security hits and missing required language.",
    )
    return parser.parse_args()


def is_excluded(path: Path, repo_root: Path) -> bool:
    try:
        rel_parts = path.relative_to(repo_root).parts
    except ValueError:
        rel_parts = path.parts
    joined = "/".join(rel_parts)
    if any(part in EXCLUDED_DIRS for part in rel_parts):
        return True
    return any(marker in joined for marker in ("assets/fonts/", "screenshots/"))


def iter_files(repo_root: Path, roots: Iterable[str]) -> Iterable[Path]:
    for root_name in roots:
        root = (repo_root / root_name).resolve()
        if not root.exists():
            continue
        if root.is_file():
            candidates = [root]
        else:
            candidates = root.rglob("*")
        for path in candidates:
            if not path.is_file():
                continue
            if is_excluded(path, repo_root):
                continue
            if path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            yield path


def line_has_string_literal_term(line: str, term: str) -> bool:
    return any(term in match.group(0) for match in STRING_LITERAL_RE.finditer(line))


def classify_hit(path: Path, repo_root: Path, term: str, line_text: str) -> tuple[str, str]:
    rel = path.relative_to(repo_root).as_posix()
    suffix = path.suffix.lower()

    if term in SECURITY_TERMS:
        return "security", "secret or auth marker must not appear in scanned files"

    if any(rel.startswith(marker) for marker in VISIBLE_DOC_ROOT_MARKERS):
        if suffix in VISIBLE_ASSET_SUFFIXES:
            return "visible", "mockup or generated visible asset"

    if suffix == ".swift":
        if line_has_string_literal_term(line_text, term):
            return "visible", "Swift string literal may render in UI"
        return "internal", "Swift implementation reference, review if exposed through UI"

    if suffix in {".plist", ".strings"}:
        return "visible", "bundle metadata or localized strings can surface to users"

    if term in DASH_TERMS:
        return "visible", "dash character in scanned text asset"

    return "internal", "non-visible documentation or implementation file"


def scan(repo_root: Path, roots: list[str]) -> dict:
    hits: list[Hit] = []
    allowed_locations: dict[str, list[str]] = {term: [] for term in ALLOWED_TERMS}
    scanned_files: list[str] = []

    for path in sorted(set(iter_files(repo_root, roots))):
        rel = path.relative_to(repo_root).as_posix()
        scanned_files.append(rel)
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        for line_no, line in enumerate(text.splitlines(), start=1):
            for term in FORBIDDEN_TERMS:
                if term in line:
                    classification, reason = classify_hit(path, repo_root, term, line)
                    hits.append(Hit(term, rel, line_no, classification, reason))
            for term in ALLOWED_TERMS:
                if term in line:
                    loc = f"{rel}:{line_no}"
                    if loc not in allowed_locations[term]:
                        allowed_locations[term].append(loc)

    missing_allowed = [term for term, locations in allowed_locations.items() if not locations]
    visible_hits = [hit for hit in hits if hit.classification == "visible"]
    security_hits = [hit for hit in hits if hit.classification == "security"]
    internal_hits = [hit for hit in hits if hit.classification == "internal"]

    return {
        "repo_root": str(repo_root),
        "roots": roots,
        "scanned_file_count": len(scanned_files),
        "scanned_files": scanned_files,
        "hits": [asdict(hit) for hit in hits],
        "visible_hit_count": len(visible_hits),
        "security_hit_count": len(security_hits),
        "internal_hit_count": len(internal_hits),
        "allowed_locations": allowed_locations,
        "missing_allowed_terms": missing_allowed,
    }


def print_text_report(result: dict, *, strict_internal: bool) -> None:
    print("Noom iOS copy/security scan")
    print(f"Repo: {result['repo_root']}")
    print(f"Roots: {', '.join(result['roots'])}")
    print(f"Scanned files: {result['scanned_file_count']}")
    print(
        "Hits: "
        f"visible={result['visible_hit_count']} "
        f"security={result['security_hit_count']} "
        f"internal={result['internal_hit_count']}"
    )
    print("Caveat: internal Swift SDK references can be acceptable if they do not render in visible UI.")
    print("This report omits matched line contents so secret values are never printed.")

    if result["hits"]:
        print("\nForbidden term hits:")
        for hit in result["hits"]:
            print(
                f"  [{hit['classification']}] {hit['term']!r} "
                f"{hit['path']}:{hit['line']} - {hit['reason']}"
            )
    else:
        print("\nForbidden term hits: none")

    print("\nRequired language:")
    for term in ALLOWED_TERMS:
        locations = result["allowed_locations"].get(term, [])
        if locations:
            preview = ", ".join(locations[:8])
            more = "" if len(locations) <= 8 else f" plus {len(locations) - 8} more"
            print(f"  [present] {term!r}: {preview}{more}")
        else:
            print(f"  [missing] {term!r}")

    failures = []
    if result["visible_hit_count"]:
        failures.append("visible forbidden terms")
    if result["security_hit_count"]:
        failures.append("security markers")
    if result["missing_allowed_terms"]:
        failures.append("missing required language")
    if strict_internal and result["internal_hit_count"]:
        failures.append("internal forbidden terms")

    if failures:
        print(f"\nFAIL: {', '.join(failures)}")
    else:
        print("\nPASS")


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    roots = args.roots or DEFAULT_SCAN_ROOTS
    result = scan(repo_root, roots)

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print_text_report(result, strict_internal=args.strict_internal)

    failed = bool(
        result["visible_hit_count"]
        or result["security_hit_count"]
        or result["missing_allowed_terms"]
        or (args.strict_internal and result["internal_hit_count"])
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
