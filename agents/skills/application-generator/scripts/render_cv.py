#!/usr/bin/env python3
"""Merge a schema-version-3 CV override with its narrative and render PDF/UA-1."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

import yaml
from PIL import Image, ImageOps

SKILL_ROOT = Path(__file__).resolve().parents[1]
TEMPLATES_DIR = SKILL_ROOT / "templates"
FONTS_CONFIG = SKILL_ROOT / "fonts.config"
FONTCACHE_DIR = SKILL_ROOT / "fontcache"

# The template stylesheet is intentionally print-first.  Keep preview-only
# presentation here so the self-contained HTML artifact opens as centered A4
# sheets in a browser without changing the PDF layout.
SCREEN_CSS = """
@media screen {
    html {
        background: #e5e5e5;
    }

    body {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12mm;
        min-width: 210mm;
        padding: 12mm 0;
    }

    .cv-page {
        flex: 0 0 auto;
        margin-left: auto;
        margin-right: auto;
        box-shadow: 0 1mm 3mm rgb(0 0 0 / 20%);
    }

    /* The sidebar belongs only to the first page in the browser preview. */
    .page-2,
    .project-page,
    .history-page {
        background: #ffffff;
    }

    .page-2::before,
    .project-page::before,
    .history-page::before {
        display: none;
    }
}
"""

_DEFAULT_MINGW_BIN = Path(r"C:\tools\msys64\mingw64\bin")
_DEFAULT_VERAPDF = Path(r"C:\tools\verapdf-1.30.2\verapdf.bat")

_BCP47_RE = re.compile(r"^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$")


PHOTO_SIZE = (480, 600)
MINIMUM_PHOTO_SIZE = (480, 600)
MAX_UPPERCASE_COMPETENCY_SUFFIX_CHARS = 22
class PayloadError(ValueError):
    pass


def _mapping(value: Any, path: str, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PayloadError(f"{path} must be a mapping")
    unknown = set(value) - keys
    missing = keys - set(value)
    if unknown:
        raise PayloadError(f"{path} contains unknown field(s): {', '.join(sorted(unknown))}")
    if missing:
        raise PayloadError(f"{path} is missing required field(s): {', '.join(sorted(missing))}")
    return value


def _text(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PayloadError(f"{path} must be a non-empty string")
    if any(ord(char) < 32 and char not in "\n\t" for char in value):
        raise PayloadError(f"{path} contains unsupported control characters")
    if "[UNKNOWN:" in value:
        raise PayloadError(f"{path} contains an unresolved UNKNOWN placeholder")
    return value


def _text_list(value: Any, path: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise PayloadError(f"{path} must be a non-empty list")
    return [_text(item, f"{path}[{index}]") for index, item in enumerate(value)]


def _validate_competency_heading(value: str, path: str) -> None:
    """Reject an unbreakable uppercase ``& …`` heading suffix that crosses the timeline."""
    _, separator, suffix = value.partition(" & ")
    unbreakable_suffix = f"& {suffix}" if separator else ""
    if (
        unbreakable_suffix.isupper()
        and len(unbreakable_suffix) > MAX_UPPERCASE_COMPETENCY_SUFFIX_CHARS
    ):
        raise PayloadError(
            f"{path} has an unbreakable uppercase suffix {unbreakable_suffix!r} that exceeds "
            "the 40 mm competency-heading column; shorten it or use title case."
        )


def _section(value: Any, path: str, *, item_key: str = "items") -> dict[str, Any]:
    section = _mapping(value, path, {"heading", item_key})
    _text(section["heading"], f"{path}.heading")
    _text_list(section[item_key], f"{path}.{item_key}") if all(isinstance(x, str) for x in section[item_key]) else None
    if not isinstance(section[item_key], list) or not section[item_key]:
        raise PayloadError(f"{path}.{item_key} must be a non-empty list")
    return section


def _merge(narrative: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Apply the deliberately small, safe override surface to the baseline."""
    override_root = {"schema_version", "language", "subtitle", "photo", "profile", "competencies", "technology", "selected_projects", "project_overview", "employment", "cover_letter"}
    unknown = set(override) - override_root
    if unknown:
        raise PayloadError(f"input contains protected or unknown field(s): {', '.join(sorted(unknown))}")
    if override.get("schema_version") != 3:
        raise PayloadError("input.schema_version must be 3")
    if override.get("language") != narrative["language"]:
        raise PayloadError("input.language must match narrative.language")

    merged = json.loads(json.dumps(narrative))
    if "subtitle" in override:
        merged["subtitle"] = _text(override["subtitle"], "input.subtitle")
    if "photo" in override:
        if override["photo"] is not None:
            raise PayloadError("input.photo must be null for the no-photo renderer")
        merged["photo"] = None
    for name in ("profile", "competencies", "technology", "selected_projects", "project_overview"):
        if name not in override:
            continue
        patch = _mapping(override[name], f"input.{name}", {"items"})
        if not isinstance(patch["items"], list) or not patch["items"]:
            raise PayloadError(f"input.{name}.items must be a non-empty list")
        if name not in merged:
            raise PayloadError(f"input.{name} has no narrative section to supply its heading")
        merged[name]["items"] = patch["items"]

    # An optional overview may be declared in the narrative solely to own its
    # language-specific headings. It is absent from the rendered payload until
    # either baseline or override supplies items.
    if "project_overview" in merged and not merged["project_overview"].get("items"):
        merged.pop("project_overview")

    if "employment" in override:
        patch = _mapping(override["employment"], "input.employment", {"items"})
        if not isinstance(patch["items"], list) or not patch["items"]:
            raise PayloadError("input.employment.items must be a non-empty list")
        by_period = {item["period"]: item for item in merged["employment"]["items"]}
        for index, item in enumerate(patch["items"]):
            entry = _mapping(item, f"input.employment.items[{index}]", {"period", "title", "points"})
            period = _text(entry["period"], f"input.employment.items[{index}].period")
            if period not in by_period:
                raise PayloadError(f"input.employment.items[{index}].period does not identify a narrative record")
            _text(entry["title"], f"input.employment.items[{index}].title")
            _text_list(entry["points"], f"input.employment.items[{index}].points")
            by_period[period]["title"] = entry["title"]
            by_period[period]["points"] = entry["points"]
    return merged


def validate_payload(raw: Any) -> dict[str, Any]:
    required_root_keys = {
        "schema_version", "language", "title", "subtitle", "contact", "links", "profile",
        "competencies", "technology", "languages", "employment", "education", "selected_projects",
    }
    allowed_root_keys = required_root_keys | {"photo", "project_overview"}
    if not isinstance(raw, dict):
        raise PayloadError("payload must be a mapping")
    unknown = set(raw) - allowed_root_keys
    missing = required_root_keys - set(raw)
    if unknown:
        raise PayloadError(f"payload contains unknown field(s): {', '.join(sorted(unknown))}")
    if missing:
        raise PayloadError(f"payload is missing required field(s): {', '.join(sorted(missing))}")
    data = raw
    if data["schema_version"] != 3:
        raise PayloadError("narrative.schema_version must be 3")

    _text(data["title"], "title")
    _text(data["subtitle"], "subtitle")

    lang = _text(data["language"], "language")
    if not _BCP47_RE.match(lang):
        raise PayloadError(
            f"language must be a valid BCP-47 language tag; received {lang!r}"
        )

    photo_value = data.get("photo")
    if photo_value is not None:
        photo_path = Path(_text(photo_value, "photo")).expanduser()
        if not photo_path.is_absolute():
            raise PayloadError("photo.path must be an absolute local path")
        if not photo_path.is_file():
            raise PayloadError(f"photo.path does not exist: {photo_path}")
        try:
            with Image.open(photo_path) as image:
                width, height = image.size
                image.verify()
        except Exception as exc:
            raise PayloadError(f"photo.path is not a readable image: {exc}") from exc
        if not math.isclose(
            width / height,
            MINIMUM_PHOTO_SIZE[0] / MINIMUM_PHOTO_SIZE[1],
            abs_tol=0.002,
        ):
            raise PayloadError(
                f"photo must have a 4:5 aspect ratio; received {width}x{height}"
            )
        if width < MINIMUM_PHOTO_SIZE[0] or height < MINIMUM_PHOTO_SIZE[1]:
            raise PayloadError(
                "photo is below 300-DPI-equivalent resolution; "
                f"need at least {MINIMUM_PHOTO_SIZE[0]}x{MINIMUM_PHOTO_SIZE[1]}, "
                f"received {width}x{height}"
            )

    contact = _mapping(data["contact"], "contact", {"adress", "tel", "email"})
    for key in ("adress", "tel", "email"):
        _text(contact[key], f"contact.{key}")

    _section(data["profile"], "profile")
    for section_name in ("competencies", "technology"):
        section = _section(data[section_name], section_name)
        for index, item in enumerate(section["items"]):
            entry = _mapping(item, f"{section_name}.items[{index}]", {"heading", "points"})
            _text(entry["heading"], f"{section_name}.items[{index}].heading")
            if section_name == "competencies":
                _validate_competency_heading(entry["heading"], f"{section_name}.items[{index}].heading")
            _text_list(entry["points"], f"{section_name}.items[{index}].points")
    _section(data["languages"], "languages")
    links = _section(data["links"], "links")
    for index, item in enumerate(links["items"]):
        entry = _mapping(item, f"links.items[{index}]", {"label", "value"})
        _text(entry["label"], f"links.items[{index}].label")
        _text(entry["value"], f"links.items[{index}].value")

    for section_name in ("employment", "education"):
        section = _mapping(data[section_name], section_name, {"heading", "items"})
        _text(section["heading"], f"{section_name}.heading")
        if not isinstance(section["items"], list) or not section["items"]:
            raise PayloadError(f"{section_name}.items must be a non-empty list")
        keys = {"period", "title", "organization", "points"}
        for index, item in enumerate(section["items"]):
            entry = _mapping(item, f"{section_name}.items[{index}]", keys)
            for key in keys - {"points"}:
                _text(entry[key], f"{section_name}.items[{index}].{key}")
            _text_list(entry["points"], f"{section_name}.items[{index}].points")
    selected = _mapping(data["selected_projects"], "selected_projects", {"heading", "items"})
    if not isinstance(selected["items"], list) or not selected["items"]:
        raise PayloadError("selected_projects.items must be a non-empty list")
    for index, item in enumerate(selected["items"]):
        entry = _mapping(item, f"selected_projects.items[{index}]", {"title", "role", "text", "points", "technologies"})
        _text(entry["title"], f"selected_projects.items[{index}].title")
        if entry["role"] is not None: _text(entry["role"], f"selected_projects.items[{index}].role")
        _text(entry["text"], f"selected_projects.items[{index}].text")
        _text_list(entry["points"], f"selected_projects.items[{index}].points")
        _text_list(entry["technologies"], f"selected_projects.items[{index}].technologies")
    if "project_overview" in data:
        overview = _mapping(data["project_overview"], "project_overview", {"heading", "items"})
        _text(overview["heading"], "project_overview.heading")
        if not isinstance(overview["items"], list) or not overview["items"]:
            raise PayloadError("project_overview.items must be a non-empty list")
        for index, item in enumerate(overview["items"]):
            entry = _mapping(item, f"project_overview.items[{index}]", {"period", "organization", "title", "text", "technologies"})
            for key in ("period", "organization", "title", "text"):
                _text(entry[key], f"project_overview.items[{index}].{key}")
            _text_list(entry["technologies"], f"project_overview.items[{index}].technologies")
    # Convert the public v3 schema to the renderer's small internal view.
    data["document"] = {"title": data["title"], "subtitle": data["subtitle"], "language": data["language"]}
    data["photo"] = {"path": photo_value} if photo_value is not None else None
    data["contact"] = [
        {"key": key, "value": data["contact"][key]}
        for key in ("adress", "tel", "email")
    ]
    data["profile"] = {"heading": data["profile"]["heading"], "paragraphs": data["profile"]["items"]}
    data["competencies_heading"] = data["competencies"]["heading"]
    data["competencies"] = data["competencies"]["items"]
    for item in data["competencies"]: item["items"] = item.pop("points")
    data["technology"] = {"heading": data["technology"]["heading"], "groups": [{"label": x["heading"], "items": x["points"]} for x in data["technology"]["items"]]}
    data["sidebar"] = {"links": data["links"]["items"], "languages": data["languages"]["items"], "links_heading": data["links"]["heading"], "languages_heading": data["languages"]["heading"]}
    for section_name in ("employment", "education"):
        for item in data[section_name]["items"]: item["bullets"] = item.pop("points")
    for item in data["selected_projects"]["items"]:
        item["summary"] = item.pop("text"); item["bullets"] = item.pop("points")
    if "project_overview" in data:
        overview = data["project_overview"]
        data["project_overview"] = {
            "heading": overview["heading"],
            "records": [
                {"client": item["organization"], "start": item["period"], "end": None, "end_label": None,
                 "title": item["title"], "summary": item["text"], "technologies": item["technologies"]}
                for item in overview["items"]
            ],
        }
    return data


def _make_contact_href(key: str, value: str) -> str | None:
    """Return an appropriate href for a contact item."""
    key_lower = key.casefold()
    if key_lower == "email":
        return f"mailto:{value.strip()}"
    if any(
        token in key_lower for token in ("phone", "tel")
    ):
        digits_plus = re.sub(r"[^\d+]", "", value)
        return f"tel:{digits_plus}" if digits_plus else None
    if any(
        token in key_lower
        for token in ("link", "web", "github", "portfolio", "linkedin", "url")
    ):
        return value if value.startswith(("http://", "https://")) else f"https://{value}"
    return value if value.startswith(("http://", "https://")) else None


def _keep_hyphenated_words(value: str) -> Any:
    """Return escaped HTML that keeps hyphenated words intact."""
    from markupsafe import Markup, escape  # noqa: PLC0415

    fragments: list[Any] = []
    for fragment in re.split(r"(\s+)", value):
        escaped = escape(fragment)
        if "-" in fragment:
            fragments.append(
                Markup('<span class="keep-together">')
                + escaped
                + Markup("</span>")
            )
        else:
            fragments.append(escaped)
    return Markup("").join(fragments)


def _organization_parts(organization: str) -> tuple[str, str | None]:
    company, separator, location = organization.partition(",")
    return company.strip(), location.strip() if separator and location.strip() else None


def _education_parts(organization: str) -> tuple[str, str | None]:
    institution, separator, location = organization.partition(",")
    if separator and location.strip():
        return institution.strip(), location.strip()
    name, separator, location = organization.partition(" ")
    return name, location.strip() if separator and location.strip() else None


def _format_employment_date(value: str, language: str) -> str:
    month_abbreviations = {
        "en": ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"),
        "de": ("Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"),
    }
    abbreviations = month_abbreviations.get(language.casefold().split("-", 1)[0], month_abbreviations["de"])
    if len(value) == 7 and value[:4].isdigit() and value[4] == "-" and value[5:].isdigit():
        month = int(value[5:])
        if 1 <= month <= 12:
            return f"{abbreviations[month - 1]} {value[:4]}"
    return value


def _format_employment_period(period: str, language: str) -> str:
    return " – ".join(_format_employment_date(part, language) for part in period.split(" – "))


# ── ATS validation helpers ────────────────────────────────────────────────────

def _normalize_ats(text: str) -> str:
    """NFC normalization, Unicode case-folding, and whitespace collapse for ATS comparison.

    Preserves meaningful punctuation (@, –, /, ,) and ensures that CSS
    ``text-transform: uppercase`` in the rendered PDF does not break coverage checks.
    """
    text = unicodedata.normalize("NFC", text)
    text = " ".join(text.casefold().split())
    # Extractors can insert layout whitespace next to punctuation already
    # present in the source (for example ``Entwickler-\nCoaching``). Ignore
    # that whitespace while retaining the punctuation itself.
    return re.sub(r"\s*([-/&,.])\s*", r"\1", text)


def _find_ats_token(text: str, token: str) -> int:
    """Return a whole-token position so headings don't match longer words."""
    match = re.search(rf"(?<!\w){re.escape(token)}(?!\w)", text)
    return match.start() if match else -1


def _build_ats_expected(data: dict[str, Any]) -> list[str]:
    """Build the ordered list of expected ATS content tokens from a v2 payload.

    Order follows the template DOM reading order (page 1 core section, then
    page 2 career/education), which is the intended PDF/UA structure tree order.
    """
    tokens: list[str] = []

    # cv-header
    tokens.append(data["document"]["title"])
    tokens.append(data["document"]["subtitle"])

    # contact-area
    for item in data["contact"]:
        tokens.append(item["value"])

    # sidebar-profile
    tokens.append(data["profile"]["heading"])
    tokens.extend(data["profile"]["paragraphs"])

    # competencies-section
    competencies = data["competencies"]
    if len(competencies) == 1:
        tokens.append(competencies[0]["heading"])
        tokens.extend(competencies[0]["items"])
    else:
        tokens.append(data["competencies_heading"])
        for group in competencies:
            tokens.append(group["heading"])
            tokens.extend(group["items"])

    # sidebar-links (computed the same way as _build_semantic_html)
    explicit_sidebar = data.get("sidebar")
    if explicit_sidebar:
        links = explicit_sidebar.get("links", [])
    else:
        links = [
            c for c in data["contact"]
            if any(
                tok in c["key"].casefold()
                for tok in ("link", "web", "github", "portfolio", "linkedin")
            )
        ]
    if links:
        tokens.append(explicit_sidebar["links_heading"])
        for item in links:
            tokens.append(item["label"])
            tokens.append(item["value"])

    # technology-section
    tokens.append(data["technology"]["heading"])
    for group in data["technology"]["groups"]:
        # Ampersand labels are deliberately rendered over two lines.  Validate
        # their readable terms separately because PDF extractors can omit the
        # inline separator while preserving the two text runs.
        label_parts = [part.strip() for part in group["label"].split("&", 1)]
        tokens.extend(part for part in label_parts if part)
        tokens.extend(group["items"])

    # sidebar-languages
    languages = explicit_sidebar.get("languages", []) if explicit_sidebar else []
    if languages:
        tokens.append(explicit_sidebar["languages_heading"])
        tokens.extend(languages)

    # Page 2: selected projects, when present.
    selected_projects = data.get("selected_projects")
    if selected_projects:
        tokens.append(selected_projects["heading"])
        for project in selected_projects["items"]:
            tokens.append(project["title"])
            if project["role"]:
                tokens.append(project["role"])
            tokens.append(project["summary"])
            tokens.extend(project["bullets"])
            tokens.append("Tech:")
            tokens.extend(project["technologies"])

    project_overview = data.get("project_overview")
    if project_overview:
        tokens.append(project_overview["heading"])
        for project in project_overview["records"]:
            tokens.append(project["client"])
            tokens.append(project["start"])
            if project["end"] or project["end_label"]:
                tokens.append(project["end"] or project["end_label"])
            tokens.append(project["title"])
            tokens.append(project["summary"])
            tokens.append("Tech:")
            tokens.extend(project["technologies"])

    # Following page: employment section
    tokens.append(data["employment"]["heading"])
    for item in data["employment"]["items"]:
        company, location = _organization_parts(item["organization"])
        tokens.append(company)
        if location:
            tokens.append(location)
        tokens.append(_format_employment_period(item["period"], data["document"]["language"]))
        tokens.append(item["title"])
        tokens.extend(item["bullets"])

    # Page 2: education-section
    tokens.append(data["education"]["heading"])
    for item in data["education"]["items"]:
        institution, location = _education_parts(item["organization"])
        tokens.append(institution)
        if location:
            tokens.append(location)
        tokens.append(item["period"])
        tokens.append(item["title"])
        tokens.extend(item.get("bullets") or [])

    return [t for t in tokens if t and t.strip()]


def _cleanup_artifacts(output: Path) -> None:
    """Remove all known artifacts for the output base name before rendering.

    Only removes paths inside the same directory as *output*.  Never touches
    files belonging to a different CV base name or any unrelated file.
    """
    stem = output.stem
    parent = output.resolve().parent

    targets = [
        output.resolve(),
        parent / f"{stem}.html",
        parent / f"{stem}-validation.json",
        parent / f"{stem}-failed.html",
        parent / f"{stem}-failed-validation.json",
    ]
    for target in targets:
        try:
            target.relative_to(parent)
        except ValueError:
            raise PayloadError(
                f"cleanup safety: {target} is outside the output directory {parent}"
            )
        target.unlink(missing_ok=True)

    for tmp in parent.glob(f".{stem}-*.pdf"):
        tmp.unlink(missing_ok=True)


def _validate_ats_content(pdf_path: Path, data: dict[str, Any]) -> dict[str, Any]:
    """Validate ATS content extraction against the expected payload.

    Checks:
    - Every page has extractable text (no image-only pages).
    - Every expected token is present in the full extracted text.
    - Major section headings appear exactly once.
    - Anchor ordering follows the semantic payload contract.
    - Page assignment enforces selected projects on page 2 and history on page 3.

    Returns a coverage/order summary dict.  Raises PayloadError on any failure.
    """
    from pypdf import PdfReader  # noqa: PLC0415

    reader = PdfReader(str(pdf_path))

    page_texts: list[str] = []
    for i, page in enumerate(reader.pages):
        text = (page.extract_text() or "").strip()
        if not text:
            raise PayloadError(
                f"ATS extraction: page {i + 1} contains no extractable text. "
                "The PDF must not contain image-only pages."
            )
        page_texts.append(text)

    norm_pages = [_normalize_ats(t) for t in page_texts]
    full_norm = " ".join(norm_pages)

    expected = _build_ats_expected(data)

    # Coverage: every expected token must appear somewhere in the full text.
    missing: list[str] = []
    for tok in expected:
        ntok = _normalize_ats(tok)
        if ntok and ntok not in full_norm:
            missing.append(tok[:80])
    if missing:
        raise PayloadError(
            f"ATS coverage: {len(missing)} expected value(s) not found in extracted text. "
            f"First missing: {missing[0]!r}"
        )

    # Selected-project values are part of the strict migration contract: each
    # occurrence in the source payload must have one corresponding visible
    # occurrence, including values that legitimately repeat in another field.
    selected = data.get("selected_projects")
    if selected:
        project_tokens = [selected["heading"]]
        for project in selected["items"]:
            project_tokens.extend([
                project["title"],
                *([project["role"]] if project["role"] else []),
                project["summary"],
                *project["bullets"],
                *project["technologies"],
            ])
        expected_norm = " ".join(_normalize_ats(token) for token in expected)
        for token in dict.fromkeys(project_tokens):
            normalized = _normalize_ats(token)
            expected_count = expected_norm.count(normalized)
            actual_count = full_norm.count(normalized)
            if actual_count != expected_count:
                raise PayloadError(
                    "ATS exactness: selected-project value "
                    f"{token[:80]!r} appears {actual_count} times; "
                    f"expected {expected_count}."
                )

    overview = data.get("project_overview")
    if overview:
        overview_tokens = [overview["heading"]]
        for project in overview["records"]:
            overview_tokens.extend([project["client"], project["start"]])
            if project["end"] or project["end_label"]:
                overview_tokens.append(project["end"] or project["end_label"])
            overview_tokens.extend([
                project["title"],
                project["summary"],
                *project["technologies"],
            ])
        expected_norm = " ".join(_normalize_ats(token) for token in expected)
        for token in dict.fromkeys(overview_tokens):
            normalized = _normalize_ats(token)
            expected_count = expected_norm.count(normalized)
            actual_count = full_norm.count(normalized)
            if actual_count != expected_count:
                raise PayloadError(
                    "ATS exactness: freelancer-project value "
                    f"{token[:80]!r} appears {actual_count} times; "
                    f"expected {expected_count}."
                )

    # Section-heading uniqueness: each major heading must appear exactly once.
    comp_heading = data["competencies_heading"]
    for heading in [
        data["profile"]["heading"],
        comp_heading,
        data["technology"]["heading"],
        *([data["selected_projects"]["heading"]] if data.get("selected_projects") else []),
        *([data["project_overview"]["heading"]] if data.get("project_overview") else []),
        data["employment"]["heading"],
        data["education"]["heading"],
    ]:
        nh = _normalize_ats(heading)
        if not nh:
            continue
        # A short generic heading can legitimately occur in ordinary body text
        # (for example the German heading "AUSBILDUNG" and a bullet saying
        # "Ausbildung bei ...").  PDF text extraction does not retain enough
        # semantic information to distinguish those occurrences reliably.
        # Longer, distinctive headings still receive the uniqueness check.
        if len(nh) < 12:
            continue
        count = len(re.findall(rf"(?<!\w){re.escape(nh)}(?!\w)", full_norm))
        if count == 0:
            raise PayloadError(
                f"ATS uniqueness: section heading {heading!r} not found in extracted text"
            )
        if count > 1:
            raise PayloadError(
                f"ATS uniqueness: section heading {heading!r} appears {count} times "
                "in extracted text; expected exactly once."
            )

    # Anchor ordering: title → selected projects (when present) → employment → education.
    title_norm = _normalize_ats(data["document"]["title"])
    employment_norm = _normalize_ats(data["employment"]["heading"])
    edu_norm = _normalize_ats(data["education"]["heading"])

    pos_title = full_norm.find(title_norm)
    pos_employment = _find_ats_token(full_norm, employment_norm)
    pos_edu = _find_ats_token(full_norm, edu_norm)
    project_norm = _normalize_ats(selected["heading"]) if selected else ""
    pos_project = _find_ats_token(full_norm, project_norm) if selected else -1
    overview_norm = _normalize_ats(overview["heading"]) if overview else ""
    pos_overview = _find_ats_token(full_norm, overview_norm) if overview else -1

    if pos_title < 0:
        raise PayloadError(
            f"ATS ordering: document title {data['document']['title']!r} not found"
        )
    if pos_title >= pos_employment:
        raise PayloadError(
            "ATS ordering: document title must precede the employment section in "
            f"extracted text (title@{pos_title}, employment@{pos_employment})."
        )
    if selected and not (pos_title < pos_project < pos_employment):
        raise PayloadError(
            "ATS ordering: selected projects must follow the document title and precede "
            f"employment (title@{pos_title}, projects@{pos_project}, employment@{pos_employment})."
        )
    if overview and not (pos_employment < pos_overview):
        raise PayloadError(
            "ATS ordering: project overview must follow career history "
            f"(overview@{pos_overview}, employment@{pos_employment})."
        )
    if pos_employment >= pos_edu:
        raise PayloadError(
            "ATS ordering: employment section must precede education in extracted text "
            f"(employment@{pos_employment}, education@{pos_edu})."
        )

    # Page assignment: employment heading must not appear on page 1.
    if norm_pages and employment_norm in norm_pages[0]:
        raise PayloadError(
            "ATS page-assignment: employment section found on page 1; "
            "expected on page 2 or later."
        )
    if selected:
        if len(norm_pages) < 3:
            raise PayloadError(
                "layout overflow: selected-project CV must contain at least 3 pages; "
                f"found {len(norm_pages)}."
            )
        if project_norm in norm_pages[0] or project_norm not in norm_pages[1]:
            raise PayloadError(
                "ATS page-assignment: selected projects must begin on page 2."
            )
        project_pages = [index for index, page in enumerate(norm_pages) if project_norm in page]
        employment_pages = [index for index, page in enumerate(norm_pages) if employment_norm in page]
        if not employment_pages or employment_pages[0] <= project_pages[-1]:
            raise PayloadError(
                "ATS page-assignment: employment must begin after the final selected-project page."
            )
        if not any(edu_norm in page for page in norm_pages[employment_pages[0]:]):
            raise PayloadError(
                "ATS page-assignment: education must follow employment."
            )
    if overview:
        if len(norm_pages) < 4:
            raise PayloadError(
                "ATS page-assignment: project overview must begin on page 4 or later."
            )
        if overview_norm in norm_pages[0] or overview_norm in norm_pages[1] or overview_norm in norm_pages[2]:
            raise PayloadError(
                "ATS page-assignment: project overview must begin on page 4."
            )

    total_tokens = len([t for t in expected if _normalize_ats(t)])
    return {
        "covered": total_tokens,
        "total": total_tokens,
        "ordered": True,
        "page_count": len(page_texts),
    }


def _extract_page_geometry(reader: Any) -> list[dict[str, Any]]:
    """Return a list of {page, width_pt, height_pt} records from a PdfReader."""
    result = []
    for i, page in enumerate(reader.pages):
        box = page.mediabox
        result.append({
            "page": i + 1,
            "width_pt": round(float(box.width), 3),
            "height_pt": round(float(box.height), 3),
        })
    return result


def _extract_font_inventory(reader: Any) -> list[str]:
    """Return a sorted list of BaseFont names embedded in the PDF."""
    fonts: set[str] = set()
    for page in reader.pages:
        resources = page.get("/Resources", {})
        if not hasattr(resources, "get"):
            continue
        font_dict = resources.get("/Font", {})
        if not hasattr(font_dict, "items"):
            continue
        for _, font_obj in font_dict.items():
            if hasattr(font_obj, "get"):
                base = font_obj.get("/BaseFont")
                if base:
                    fonts.add(str(base).lstrip("/"))
    return sorted(fonts)


def _validate_calibri_embedding(fonts: list[str]) -> None:
    """Fail if no Calibri face is embedded in the PDF."""
    if not any("calibri" in f.lower() for f in fonts):
        summary = ", ".join(fonts[:10]) if fonts else "none"
        raise PayloadError(
            "Calibri is not embedded in the rendered PDF. "
            f"Embedded fonts: {summary}. "
            "Ensure Calibri is installed in C:/Windows/Fonts and fontconfig is configured."
        )


def _collect_tool_versions(verapdf_path: Path) -> dict[str, str]:
    """Collect version strings for all toolchain components."""
    import weasyprint  # noqa: PLC0415
    import pypdf as _pypdf  # noqa: PLC0415

    versions: dict[str, str] = {
        "python": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "weasyprint": getattr(weasyprint, "__version__", "unknown"),
        "pypdf": getattr(_pypdf, "__version__", "unknown"),
        "verapdf": "unknown",
    }
    try:
        result = subprocess.run(
            [str(verapdf_path), "--version"],
            capture_output=True, text=True, timeout=15,
        )
        if result.stdout:
            versions["verapdf"] = result.stdout.splitlines()[0].strip()
    except Exception:
        pass
    return versions


# ── Schema-version-2 semantic rendering via WeasyPrint ───────────────────────
def _discover_mingw_bin() -> Path:
    """Return the MinGW64 bin directory containing Pango/GObject DLLs."""
    override = os.environ.get("CV_MINGW_BIN")
    if override:
        path = Path(override)
        if not path.is_dir():
            raise PayloadError(
                f"CV_MINGW_BIN not found: {path}. "
                "Set CV_MINGW_BIN to the bin directory containing libpango-1.0-0.dll."
            )
        return path
    if _DEFAULT_MINGW_BIN.is_dir():
        return _DEFAULT_MINGW_BIN
    raise PayloadError(
        "MinGW/Pango installation not found. "
        f"Expected at {_DEFAULT_MINGW_BIN}. "
        "Set CV_MINGW_BIN to the bin directory containing libpango-1.0-0.dll."
    )


def _discover_verapdf() -> Path:
    """Return the veraPDF batch script path."""
    override = os.environ.get("CV_VERAPDF")
    if override:
        path = Path(override)
        if not path.is_file():
            raise PayloadError(
                f"CV_VERAPDF not found: {path}. "
                "Set CV_VERAPDF to the verapdf.bat path."
            )
        return path
    if _DEFAULT_VERAPDF.is_file():
        return _DEFAULT_VERAPDF
    raise PayloadError(
        "veraPDF not found. "
        f"Expected at {_DEFAULT_VERAPDF}. "
        "Set CV_VERAPDF to the verapdf.bat path."
    )


def _check_verapdf_version(verapdf: Path) -> None:
    """Fail if the discovered veraPDF is not the pinned 1.30.2 release."""
    try:
        result = subprocess.run(
            [str(verapdf), "--version"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PayloadError(f"veraPDF version check failed: {exc}") from exc
    if "1.30.2" not in result.stdout:
        first_line = result.stdout.splitlines()[0] if result.stdout else "unknown"
        raise PayloadError(
            f"veraPDF 1.30.2 is required; found: {first_line}. "
            "Set CV_VERAPDF to a veraPDF 1.30.2 installation."
        )


def _setup_weasyprint_env(mingw_bin: Path) -> None:
    """Configure process-local DLL discovery and fontconfig for WeasyPrint.

    Uses os.add_dll_directory (Python 3.8+, Windows) to expose the MinGW bin
    directory to cffi without modifying the user or global PATH.  Sets
    FONTCONFIG_FILE and FC_CACHEDIR only for this renderer process.
    """
    if hasattr(os, "add_dll_directory"):
        os.add_dll_directory(str(mingw_bin))
    FONTCACHE_DIR.mkdir(parents=True, exist_ok=True)
    os.environ["FONTCONFIG_FILE"] = str(FONTS_CONFIG)
    os.environ["FC_CACHEDIR"] = str(FONTCACHE_DIR)


def _preflight_calibri(mingw_bin: Path) -> None:
    """Verify Calibri Regular, Bold, Italic, and Light resolve via fontconfig.

    Fails with an actionable message if any face is missing or falls back to
    a substitute font, preventing silent visual drift.
    """
    fc_match = mingw_bin / "fc-match.exe"
    if not fc_match.is_file():
        raise PayloadError(
            f"fc-match not found at {fc_match}. "
            "Ensure fontconfig is installed in the MinGW bin directory."
        )
    env = {
        **os.environ,
        "PATH": str(mingw_bin) + ";" + os.environ.get("PATH", ""),
        "FONTCONFIG_FILE": str(FONTS_CONFIG),
        "FC_CACHEDIR": str(FONTCACHE_DIR),
    }
    faces = [
        ("Calibri:style=Regular", "calibri.ttf"),
        ("Calibri:style=Bold", "calibrib.ttf"),
        ("Calibri:style=Italic", "calibrii.ttf"),
        ("Calibri:style=Light", "calibril.ttf"),
    ]
    for face_spec, expected_file in faces:
        try:
            result = subprocess.run(
                [str(fc_match), "--format", "%{file}", face_spec],
                capture_output=True, text=True, env=env, timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise PayloadError(f"Calibri preflight failed for {face_spec}: {exc}") from exc
        matched = result.stdout.strip()
        if expected_file.lower() not in matched.lower():
            raise PayloadError(
                f"Calibri preflight failed: {face_spec} resolved to {matched!r} "
                f"(expected a path containing {expected_file}). "
                "Ensure Calibri is installed in C:/Windows/Fonts."
            )


def _run_verapdf(pdf_path: Path, verapdf: Path) -> None:
    """Run veraPDF with the ua1 profile and fail if the PDF is not compliant."""
    try:
        result = subprocess.run(
            [str(verapdf), "--flavour", "ua1", str(pdf_path)],
            capture_output=True, text=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PayloadError(f"veraPDF invocation failed: {exc}") from exc
    if not result.stdout.strip():
        raise PayloadError(
            f"veraPDF produced no output (exit {result.returncode}): {result.stderr[:200]}"
        )
    try:
        root = ET.fromstring(result.stdout)
    except ET.ParseError as exc:
        raise PayloadError(f"veraPDF output parse error: {exc}") from exc
    for vr in root.iter("validationReport"):
        if vr.get("isCompliant", "false").lower() != "true":
            failed_rules = vr.findall(".//rule[@status='failed']")
            descs = []
            for rule in failed_rules[:5]:
                desc_el = rule.find("description")
                clause = rule.get("clause", "?")
                desc = (desc_el.text or "").strip()[:100] if desc_el is not None else ""
                descs.append(f"clause {clause}: {desc}")
            raise PayloadError(
                "PDF/UA-1 (ua1) validation failed:\n"
                + "\n".join(f"  - {d}" for d in descs)
            )


def _build_semantic_html(data: dict[str, Any], portrait_data_uri: str) -> str:
    """Render the Jinja2 CV template with the validated v2 payload."""
    import jinja2  # noqa: PLC0415

    jenv = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(TEMPLATES_DIR)),
        autoescape=True,
        undefined=jinja2.StrictUndefined,
    )
    css_content = (TEMPLATES_DIR / "cv.css").read_text(encoding="utf-8") + SCREEN_CSS
    technology_group_count = len(data["technology"]["groups"])
    if technology_group_count == 5:
        # Five tailored groups can contain wrapped labels or values.  The
        # template's base divider is sized for the compact baseline and ends
        # before the final marker in that layout.
        css_content += (
            "\n.technology-section.technology-groups-5::after "
            "{ height: auto; bottom: 7.1mm; }\n"
        )

    explicit_sidebar = data.get("sidebar")
    links = (
        explicit_sidebar["links"]
        if explicit_sidebar
        else [
            c for c in data["contact"]
            if any(
                token in c["key"].casefold()
                for token in ("link", "web", "github", "portfolio", "linkedin")
            )
        ]
    )
    languages = explicit_sidebar["languages"] if explicit_sidebar else []
    selected_projects = data.get("selected_projects")
    project_overview = data.get("project_overview")
    template = jenv.get_template("cv.html.j2")
    return template.render(
        document=data["document"],
        portrait_data_uri=portrait_data_uri,
        contact_items=data["contact"],
        profile=data["profile"],
        competencies=data["competencies"],
        competencies_heading=data["competencies_heading"],
        technology=data["technology"],
        links=links,
        links_heading=explicit_sidebar["links_heading"],
        languages=languages,
        languages_heading=explicit_sidebar["languages_heading"],
        employment=data["employment"],
        education=data["education"],
        selected_projects=selected_projects,
        project_overview=project_overview,
        css_content=css_content,
        contact_href=_make_contact_href,
        keep_hyphenated_words=_keep_hyphenated_words,
        organization_parts=_organization_parts,
        education_parts=_education_parts,
        format_employment_period=lambda period: _format_employment_period(period, data["document"]["language"]),
    )


def render_semantic(data: dict[str, Any], output: Path, *, source_yaml: Path | None = None) -> None:
    """Render a normalized schema-version-3 payload to a validated PDF/UA-1 document.

    Artifact lifecycle
    ------------------
    Before rendering, all known regular, failed, validation, and temporary
    artifacts for the requested output base name are removed.

    On success a mutually consistent triple is published:
      <stem>.pdf    — validated PDF/UA-1
      <stem>.html   — self-contained HTML (debugging and inspection)
      <stem>-validation.json — toolchain versions, hashes, PDF/UA result, ATS report

    On failure all regular artifacts are removed.  If HTML was generated before
    the failure a diagnostic pair is retained:
      <stem>-failed.html
      <stem>-failed-validation.json
    """
    import base64  # noqa: PLC0415
    import io  # noqa: PLC0415

    stem = output.stem
    parent = output.resolve().parent
    html_path = parent / f"{stem}.html"
    report_path = parent / f"{stem}-validation.json"
    failed_html_path = parent / f"{stem}-failed.html"
    failed_report_path = parent / f"{stem}-failed-validation.json"

    # ── Step 1: pre-run cleanup ─────────────────────────────────────────────
    _cleanup_artifacts(output)

    # ── Step 2: prerequisites (MinGW/Calibri must be ready before WeasyPrint) ─
    mingw_bin = _discover_mingw_bin()
    _setup_weasyprint_env(mingw_bin)
    _preflight_calibri(mingw_bin)

    from weasyprint import HTML  # noqa: PLC0415  (imported after DLL setup)
    from weasyprint.text.fonts import FontConfiguration  # noqa: PLC0415

    # ── Step 3: encode portrait ─────────────────────────────────────────────
    portrait_data_uri = ""
    if data["photo"] is not None:
        photo_path = Path(data["photo"]["path"]).expanduser()
        with Image.open(photo_path) as source:
            portrait = ImageOps.fit(
                source.convert("RGB"),
                PHOTO_SIZE,
                Image.Resampling.LANCZOS,
                centering=(0.5, 0.45),
            )
        portrait_bytes = io.BytesIO()
        portrait.save(portrait_bytes, "PNG")
        portrait_b64 = base64.b64encode(portrait_bytes.getvalue()).decode("ascii")
        portrait_data_uri = f"data:image/png;base64,{portrait_b64}"

    # ── Step 4: generate HTML (in memory; saved only on success or failure) ──
    html_content = _build_semantic_html(data, portrait_data_uri)

    # ── Steps 5–7: render, validate, publish (with failure-lifecycle cleanup) ─
    parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{stem}-", suffix=".pdf", dir=parent)
    os.close(fd)
    tmp_pdf: Path | None = Path(tmp_name)
    pdfua_compliant = False
    ats_result: dict[str, Any] | None = None
    verapdf: Path | None = None

    try:
        # veraPDF is discovered after HTML so that failures at this stage are
        # captured in the failure-diagnostics path.
        verapdf = _discover_verapdf()
        _check_verapdf_version(verapdf)

        font_config = FontConfiguration()
        assert tmp_pdf is not None
        HTML(string=html_content, base_url=str(SKILL_ROOT)).write_pdf(
            str(tmp_pdf),
            font_config=font_config,
            pdf_variant="pdf/ua-1",
        )

        _run_verapdf(tmp_pdf, verapdf)
        pdfua_compliant = True

        ats_result = _validate_ats_content(tmp_pdf, data)

        # Build validation report (requires an open PdfReader while tmp_pdf still exists)
        from pypdf import PdfReader  # noqa: PLC0415
        _reader = PdfReader(str(tmp_pdf))
        geometry = _extract_page_geometry(_reader)
        fonts = _extract_font_inventory(_reader)
        del _reader

        # Page-count overflow check: permanent role (no extras) must be ≤ 2 pages.
        _validate_calibri_embedding(fonts)

        source_hash = (
            "sha256:" + hashlib.sha256(source_yaml.read_bytes()).hexdigest()
            if source_yaml and source_yaml.is_file()
            else None
        )
        pdf_hash = "sha256:" + hashlib.sha256(tmp_pdf.read_bytes()).hexdigest()

        # Publish HTML first; hash from disk so the stored hash matches what consumers read
        # (important on Windows where write_text may translate newlines).
        html_path.write_text(html_content, encoding="utf-8")
        html_hash = "sha256:" + hashlib.sha256(html_path.read_bytes()).hexdigest()

        report: dict[str, Any] = {
            "status": "success",
            "schema_version": data["schema_version"],
            "language": data["document"].get("language"),
            "tools": _collect_tool_versions(verapdf),
            "source_hash": source_hash,
            "artifact_hashes": {"html": html_hash, "pdf": pdf_hash},
            "pdfua_result": {"compliant": True},
            "ats": ats_result,
            "page_geometry": geometry,
            "font_inventory": fonts,
        }

        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp_pdf, output)
        tmp_pdf = None  # already moved — skip unlink in finally

        # Remove any leftover failed-run diagnostics from a previous attempt.
        failed_html_path.unlink(missing_ok=True)
        failed_report_path.unlink(missing_ok=True)

    finally:
        # Always remove the temp PDF if still present.
        if tmp_pdf is not None:
            tmp_pdf.unlink(missing_ok=True)

        # If the output PDF was never published the run failed: clean regular
        # artifacts and persist failure diagnostics.
        if not output.exists():
            html_path.unlink(missing_ok=True)
            report_path.unlink(missing_ok=True)

            # Save the generated HTML as a diagnostic candidate.
            failed_html_path.write_text(html_content, encoding="utf-8")

            exc = sys.exc_info()[1]
            diag: dict[str, Any] = {
                "status": "failed",
                "error": str(exc) if exc else "unknown error",
                "pdfua_passed": pdfua_compliant,
            }
            if ats_result is not None:
                diag["ats_partial"] = ats_result
            failed_report_path.write_text(
                json.dumps(diag, ensure_ascii=False, indent=2), encoding="utf-8"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="schema-v3 YAML override source")
    parser.add_argument("--narrative", required=True, type=Path, help="schema-v3 narrative baseline")
    parser.add_argument("--projects", type=Path, help="schema-v3 projects baseline (required when project_overview is used)")
    parser.add_argument("--output", required=True, type=Path, help="explicit PDF destination")
    args = parser.parse_args()
    if args.output.suffix.lower() != ".pdf":
        parser.error("--output must end in .pdf")
    try:
        raw = yaml.safe_load(args.narrative.read_text(encoding="utf-8"))
        override = yaml.safe_load(args.input.read_text(encoding="utf-8"))
        if not isinstance(raw, dict) or not isinstance(override, dict):
            raise PayloadError("narrative and input must be mappings")
        merged = _merge(raw, override)
        if "project_overview" in merged:
            projects_path = args.projects or args.narrative.with_name("projects.yaml")
            projects = yaml.safe_load(projects_path.read_text(encoding="utf-8"))
            if not isinstance(projects, dict) or projects.get("schema_version") != 3:
                raise PayloadError("projects.schema_version must be 3 when project_overview is used")
            if projects.get("language") != raw["language"]:
                raise PayloadError("projects.language must match narrative.language")
        data = validate_payload(merged)
        render_semantic(data, args.output.resolve(), source_yaml=args.input.resolve())
    except (PayloadError, yaml.YAMLError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"error: unable to read input or write output: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
