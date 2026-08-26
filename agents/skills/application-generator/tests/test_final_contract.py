from __future__ import annotations

import sys
from pathlib import Path

import pytest

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "scripts"))
from render_cv import PayloadError, _build_semantic_html, _merge, validate_payload  # noqa: E402


def narrative() -> dict:
    return {
        "schema_version": 3,
        "language": "de", "title": "A", "subtitle": "B",
        "photo": "C:\\missing.png", "contact": {"adress": "A", "tel": "1", "email": "a@b.c"},
        "links": {"heading": "LINKS", "items": [{"label": "Web", "value": "example.test"}]},
        "profile": {"heading": "ÜBER MICH", "items": ["Text"]},
        "competencies": {"heading": "KOMPETENZEN", "items": [{"heading": "A", "points": ["B"]}]},
        "technology": {"heading": "TECH", "items": [{"heading": "Sprachen", "points": ["Python"]}]},
        "languages": {"heading": "SPRACHEN", "items": ["DEUTSCH - Muttersprache"]},
        "employment": {"heading": "BERUF", "items": [{"period": "2020", "title": "Dev", "organization": "Acme", "points": ["Build"]}]},
        "education": {"heading": "AUSBILDUNG", "items": [{"period": "2010", "title": "IT", "organization": "School", "points": ["Fachrichtung Technik"]}]},
        "selected_projects": {"heading": "PROJEKTE", "items": [{"title": "P", "role": None, "text": "Text", "points": ["Point"], "technologies": ["Python"]}]},
    }


def override(**values: object) -> dict:
    result: dict = {"schema_version": 3, "language": "de"}
    result.update(values)
    return result


def test_schema_v3_merges_baseline_and_sparse_employment_patch() -> None:
    merged = _merge(narrative(), override(
        subtitle="Engineering Leader",
        employment={"items": [{"period": "2020", "title": "Lead", "points": ["Lead"]}]},
    ))
    assert merged["employment"]["items"][0]["organization"] == "Acme"
    assert merged["employment"]["items"][0]["title"] == "Lead"
    assert merged["subtitle"] == "Engineering Leader"


def test_protected_sections_and_language_mismatches_fail() -> None:
    with pytest.raises(PayloadError, match="protected"):
        _merge(narrative(), override(languages={"items": ["ENGLISH - C2"]}))
    with pytest.raises(PayloadError, match="must match"):
        _merge(narrative(), {"schema_version": 3, "language": "en"})
    with pytest.raises(PayloadError, match="unknown field"):
        _merge(narrative(), override(profile={"heading": "ABOUT ME", "items": ["Text"]}))


def test_canonical_schema_uses_items_and_points() -> None:
    with pytest.raises(PayloadError, match="photo.path does not exist"):
        validate_payload(_merge(narrative(), override()))


def test_heading_only_optional_project_overview_is_not_rendered() -> None:
    base = narrative()
    base["project_overview"] = {"heading": "PROJEKTÜBERSICHT"}
    assert "project_overview" not in _merge(base, override())


def test_baseline_employment_is_normalized_for_the_template() -> None:
    base = narrative()
    base["photo"] = str((SKILL_ROOT.parents[2] / "secrets" / "cv" / "Foto.png").resolve())
    data = validate_payload(_merge(base, override()))
    html = _build_semantic_html(data, "data:image/png;base64,")
    assert "BERUF" in html
    assert "AUSBILDUNG" in html
    assert '<aside class="sidebar-content">' in html


def test_five_technology_groups_extend_the_timeline_divider() -> None:
    base = narrative()
    base["photo"] = str((SKILL_ROOT.parents[2] / "secrets" / "cv" / "Foto.png").resolve())
    base["technology"]["items"] = [
        {"heading": f"Gruppe {index}", "points": ["Python"]}
        for index in range(1, 6)
    ]
    data = validate_payload(_merge(base, override()))
    html = _build_semantic_html(data, "data:image/png;base64,")
    assert ".technology-section.technology-groups-5::after { height: 60.5mm; }" in html


def test_technology_label_keeps_ampersand_continuation_together_when_wrapping() -> None:
    base = narrative()
    base["photo"] = str((SKILL_ROOT.parents[2] / "secrets" / "cv" / "Foto.png").resolve())
    base["technology"]["items"][0]["heading"] = "Architektur & Entwicklung"
    data = validate_payload(_merge(base, override()))
    html = _build_semantic_html(data, "data:image/png;base64,")
    assert '<span class="tech-label-continuation"> &amp; Entwicklung</span>' in html
    assert ".tech-label-continuation {\n    /* Keep the ampersand with its continuation." in html
    assert "white-space: nowrap;" in html


def test_unbreakable_competency_heading_that_crosses_timeline_fails() -> None:
    base = narrative()
    base["photo"] = str((SKILL_ROOT.parents[2] / "secrets" / "cv" / "Foto.png").resolve())
    base["competencies"]["items"][0]["heading"] = "DELIVERY & STAKEHOLDER ALIGNMENT"
    with pytest.raises(PayloadError, match="unbreakable uppercase suffix"):
        validate_payload(_merge(base, override()))


def test_documentation_describes_schema_v3_and_required_narrative() -> None:
    readme = (SKILL_ROOT / "README.md").read_text(encoding="utf-8")
    skill = (SKILL_ROOT / "SKILL.md").read_text(encoding="utf-8")
    assert "schema-version-3" in readme
    assert "--narrative" in readme
    assert "`schema_version: 3`" in skill
