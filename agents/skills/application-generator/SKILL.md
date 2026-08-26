---
name: application-generator
description: Create evidence-bound CVs and cover letters for job applications. Use for CV/resume or cover-letter/Anschreiben requests.
---

Create truthful, tailored application documents from secured facts. The schema-v3 (`schema_version: 3`) override YAML is the source of each rendered document; hand off only validated PDFs.

## Shared start

1. Identify the requested output: CV, cover letter, or both. Start `grilling` and confirm, one decision at a time, the document language, role, leadership-versus-technical emphasis, and confirmed motivation. **Done:** the requested documents and positioning are confirmed.

2. For a supplied job URL, inspect the rendered listing with `playwright-cli` before using another source. Keep the persistent profile so the user can sign in when needed:

   ```powershell
   playwright-cli -s=application-generator open `
     --profile="$env:TEMP\application-generator-playwright-profile" `
     "<job-url>"
   playwright-cli -s=application-generator snapshot
   ```

   Verify the actual role and its responsibilities or requirements in the snapshot. If the description is unavailable, ask the user to sign in or provide the description, then retry with that profile. **Done:** the description is visible or supplied directly.

3. Research the named company from first-party web sources. Classify it as the actual employer or a recruiter/personaldienstleister, and save the conclusion with source links in `agents/skills/application-generator/output/`.

   - For an actual employer, use verified, role-relevant findings to tailor the documents.
   - For a recruiter, tailor only to the verified role requirements and use neutral recipient wording; the end client remains unspecified.

   **Done:** the company classification and eligible research are recorded.

4. Read the matching-language `secrets/cv/narrative*.yaml`, plus the verified listing and eligible research. Build an evidence ledger before drafting. Applicant statements support motivation only; every professional claim must map to secured CV data. **Done:** every intended YAML claim maps to secured data or confirmed motivation.

## CV

1. Read `secrets/cv/projects.yaml` and apply the project-source rules below. Propose three to five relevant, evidence-backed `selected_projects` with a relevance reason and obtain confirmation of selection and order. **Done:** the project selection and order are confirmed.

2. Create the schema-v3 override in `agents/skills/application-generator/output/`, then render it:

   ```powershell
   python agents/skills/application-generator/scripts/render_cv.py `
     --narrative <matching-language-narrative-yaml> `
     --input <override-yaml> `
     --output <cv-pdf>
   ```

   **Done:** matching PDF, self-contained HTML, and validation JSON exist; PDF/UA-1 and ATS validation pass.

## Cover letter

1. Draft two to five evidence-backed paragraphs that explain the fit without duplicating the CV. Add this section to the same override YAML:

   ```yaml
   cover_letter:
     recipient:
       - Company name
       - Hiring contact or team
       - City, country
     subject: Application for Role
     salutation: Dear Hiring Team
     text:
       - First evidence-backed paragraph.
       - Second evidence-backed paragraph.
   ```

   **Done:** the letter uses only evidence ledger claims and confirmed motivation.

2. Render the letter:

   ```powershell
   python agents/skills/application-generator/scripts/render_cover_letter.py `
     --narrative <matching-language-narrative-yaml> `
     --input <override-yaml> `
     --output <cover-letter-pdf>
   ```

   **Done:** matching PDF, self-contained HTML, and validation JSON exist; the PDF is one page, PDF/UA-1 passes, and every expected value is extractable.

## Source and layout rules

- `narrative.yaml` owns identity, headings, languages, education, employment, and default content. The override may change `subtitle`, allowed section items, sparse employment patches by `period`, and `cover_letter`.
- `projects.yaml.items` is the sole source for `project_overview.items`; use it only for contract-focused applications and in the narrative language. `projects.yaml.narrative_references` supports tailoring and does not supply rendered CV projects.
- Use plain YAML and evidence-led wording. Include only secured credentials, responsibilities, metrics, technologies, language levels, dates, employers, and outcomes.
- Put selected projects from page 2 onward; career history follows their final page. Put `project_overview`, when used, from page 4 onward.
- Keep the CV's first page within its supported competency and technology content. Keep cover letters to one A4 page using normal hyphens.

## Handoff

Retain the override YAML, evidence ledger, and company-research note in `agents/skills/application-generator/output/`. Hand off the validated PDF and, when useful, its HTML and validation JSON.
