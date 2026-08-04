#!/usr/bin/env python3
"""Standalone ATS validator for CV PDFs rendered with schema version 3.

Applies the same normalization, coverage, ordering, uniqueness, and
page-assignment rules as the schema-version-3 renderer so that extraction
failures can be diagnosed independently of rendering.

Usage::

    python validate_ats.py --input override.yaml --narrative narrative.yaml --pdf cv.pdf
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

# Reuse the shared validation implementation from render_cv (same directory).
sys.path.insert(0, str(Path(__file__).parent))
from render_cv import (  # noqa: E402
    PayloadError,
    _merge,
    _mapping,
    validate_payload,
    _validate_ats_content,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input", required=True, type=Path, help="schema-v3 override YAML"
    )
    parser.add_argument("--narrative", required=True, type=Path, help="schema-v3 narrative baseline")
    parser.add_argument("--projects", type=Path, help="schema-v3 projects YAML baseline for project_overview")
    parser.add_argument("--pdf", required=True, type=Path, help="PDF file to validate")
    args = parser.parse_args()

    if not args.pdf.is_file():
        print(f"error: PDF not found: {args.pdf}", file=sys.stderr)
        return 2

    try:
        narrative = yaml.safe_load(args.narrative.read_text(encoding="utf-8"))
        override = yaml.safe_load(args.input.read_text(encoding="utf-8"))
        if not isinstance(narrative, dict) or not isinstance(override, dict):
            raise PayloadError("narrative and input must be mappings")
        merged = _merge(narrative, override)
        if "project_overview" in merged:
            projects_path = args.projects or args.narrative.with_name("projects.json")
            projects = yaml.safe_load(projects_path.read_text(encoding="utf-8"))
            if not isinstance(projects, dict) or projects.get("schema_version") != 3:
                raise PayloadError("projects.schema_version must be 3 when project_overview is used")
            if projects.get("language") != narrative["language"]:
                raise PayloadError("projects.language must match narrative.language")
        data = validate_payload(merged)
        result = _validate_ats_content(args.pdf, data)
        print(
            f"ATS validation passed: {result['covered']}/{result['total']} tokens covered, "
            f"ordered={result['ordered']}, pages={result['page_count']}"
        )
    except (PayloadError, yaml.YAMLError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
