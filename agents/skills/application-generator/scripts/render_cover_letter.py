#!/usr/bin/env python3
"""Render cover_letter.text from a CV override to a validated one-page PDF/UA-1."""

from __future__ import annotations

import argparse
from datetime import date
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml

import render_cv as cv

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "templates" / "cover_letter.html.j2"


class LetterError(ValueError):
    pass


def _text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise LetterError(f"{field} must be a non-empty string")
    if "[UNKNOWN:" in value or any(ord(char) < 32 and char not in "\n\t" for char in value):
        raise LetterError(f"{field} contains an unsupported placeholder or control character")
    if any(char in value for char in ("\u00ad", "\u200b", "\u2010", "\u2011")):
        raise LetterError(f"{field} contains a prohibited hyphenation character")
    return value


def _normalise(value: str) -> str:
    value = re.sub(r"(?<=\w)-\s+(?=\w)", "-", value)
    return re.sub(r"\s+", " ", value).casefold().strip()


def _format_today(language: str) -> str:
    today = date.today()
    if language.casefold().split("-", 1)[0] == "de":
        months = ("Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember")
        return f"{today.day}. {months[today.month - 1]} {today.year}"
    return f"{today.day} {today.strftime('%B')} {today.year}"


def _cover_letter(narrative: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    if override.get("schema_version") != 3 or override.get("language") != narrative.get("language"):
        raise LetterError("input must be schema-v3 and use the narrative language")
    section = override.get("cover_letter")
    if not isinstance(section, dict) or set(section) != {"text", "recipient", "subject", "salutation"}:
        raise LetterError("input.cover_letter must contain exactly text, recipient, subject, and salutation")
    paragraphs = section["text"]
    if not isinstance(paragraphs, list) or not 2 <= len(paragraphs) <= 5:
        raise LetterError("input.cover_letter.text must contain two to five paragraphs")
    for index, paragraph in enumerate(paragraphs):
        _text(paragraph, f"input.cover_letter.text[{index}]")
    recipient = section["recipient"]
    if not isinstance(recipient, list) or not recipient:
        raise LetterError("input.cover_letter.recipient must be a non-empty list")
    for index, value in enumerate(recipient):
        _text(value, f"input.cover_letter.recipient[{index}]")
    contact = narrative.get("contact")
    if not isinstance(contact, dict):
        raise LetterError("narrative.contact is required")
    subtitle = _text(override.get("subtitle", narrative.get("subtitle")), "subtitle")
    salutation = _text(section["salutation"], "input.cover_letter.salutation")
    if not salutation.endswith(","):
        salutation += ","
    return {
        "language": _text(narrative.get("language"), "narrative.language"),
        "name": _text(narrative.get("title"), "narrative.title"),
        "subtitle": subtitle,
        "address": _text(contact.get("adress"), "narrative.contact.adress"),
        "phone": _text(contact.get("tel"), "narrative.contact.tel"),
        "email": _text(contact.get("email"), "narrative.contact.email"),
        "linkedin": next((item["value"] for item in narrative.get("links", {}).get("items", []) if item.get("label") == "LinkedIn"), ""),
        "recipient": recipient,
        "date": _format_today(_text(narrative.get("language"), "narrative.language")),
        "subject": _text(section["subject"], "input.cover_letter.subject"),
        "salutation": salutation,
        "paragraphs": paragraphs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--narrative", required=True, type=Path)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.suffix.lower() != ".pdf":
        parser.error("--output must end in .pdf")
    try:
        narrative = yaml.safe_load(args.narrative.read_text(encoding="utf-8"))
        override = yaml.safe_load(args.input.read_text(encoding="utf-8"))
        if not isinstance(narrative, dict) or not isinstance(override, dict):
            raise LetterError("narrative and input must be mappings")
        letter = _cover_letter(narrative, override)
        cv._setup_weasyprint_env(cv._discover_mingw_bin())
        cv._preflight_calibri(cv._discover_mingw_bin())
        import jinja2
        from pypdf import PdfReader
        from weasyprint import HTML
        from weasyprint.text.fonts import FontConfiguration

        html = jinja2.Environment(loader=jinja2.FileSystemLoader(str(TEMPLATE.parent)), autoescape=True).get_template(TEMPLATE.name).render(letter=letter)
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        HTML(string=html, base_url=str(ROOT)).write_pdf(str(output), font_config=FontConfiguration(), pdf_variant="pdf/ua-1")
        cv._run_verapdf(output, cv._discover_verapdf())
        reader = PdfReader(str(output))
        if len(reader.pages) != 1:
            raise LetterError(f"cover letter must fit on one page; rendered {len(reader.pages)} pages")
        extracted = "\n".join(page.extract_text() for page in reader.pages)
        missing = [value for value in (letter["name"], letter["subtitle"], *letter["recipient"], letter["date"], letter["subject"], letter["salutation"], *letter["paragraphs"]) if _normalise(value) not in _normalise(extracted)]
        if missing:
            raise LetterError(f"text extraction is missing: {missing[0]!r}")
        if any(char in extracted for char in ("\u00ad", "\u200b", "\u2010", "\u2011")):
            raise LetterError("extracted PDF text contains a prohibited hyphenation character")
        fonts = cv._extract_font_inventory(reader)
        cv._validate_calibri_embedding(fonts)
        output.with_suffix(".html").write_text(html, encoding="utf-8")
        output.with_name(f"{output.stem}-validation.json").write_text(json.dumps({"status": "success", "schema_version": 3, "pdfua_result": {"compliant": True}, "pages": 1, "source_hash": "sha256:" + hashlib.sha256(args.input.read_bytes()).hexdigest(), "fonts": fonts}, indent=2), encoding="utf-8")
    except (LetterError, cv.PayloadError, yaml.YAMLError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
