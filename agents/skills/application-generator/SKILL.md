---
name: application-generator
description: Create evidence-bound CVs and cover letters for job applications. Use for CV/resume or cover-letter/Anschreiben requests.
---

Create truthful, tailored application documents from secured facts. The schema-v3 (`schema_version: 3`) override YAML is the source of each rendered document; hand off only validated PDFs.

## Shared start

1. Identify the requested output: CV, cover letter, or both. Start `grilling` and confirm, one decision at a time, the document language, role, leadership-versus-technical emphasis, photo preference for CVs, and confirmed motivation. For freelancer, contracting, project, and B2B applications, omit the motivation decision and all motivation language from the generated artifacts; positioning is complete once the other decisions are confirmed. **Done:** the requested documents and positioning are confirmed.

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

1. Follow the confirmed photo preference. Omit `photo` from the override to use the secured narrative portrait, or set `photo: null` for the supported no-photo layout. Do not replace the secured portrait from an application override.

2. Read `secrets/cv/projects.yaml` and apply the project-source rules below. Propose three to five relevant, evidence-backed `selected_projects` with a relevance reason and obtain confirmation of selection and order. **Done:** the project selection and order are confirmed.

3. Create the schema-v3 override in `agents/skills/application-generator/output/`, then render it:

   ```powershell
   python agents/skills/application-generator/scripts/render_cv.py `
     --narrative <matching-language-narrative-yaml> `
     --input <override-yaml> `
     --output <cv-pdf>
   ```

   **Done:** matching PDF, self-contained HTML, and validation JSON exist; PDF/UA-1 and ATS validation pass.

4. Run an automated page-1 layout guard against the self-contained HTML before handoff. Serve the HTML locally, load it with Playwright, emulate `print` media, and wait for `document.fonts.ready`. Check every `.competency-heading` under `KERNKOMPETENZEN` and every `.tech-label` under `TECHNOLOGIE STACK` rather than checking only known strings.

   For each label, select its contents with a DOM `Range` and compare the painted rectangle with the label's assigned rectangle. Fail when the painted right edge exceeds the assigned right edge, when `scrollWidth` exceeds `clientWidth`, or when the painted bottom exceeds the containing `.competency-group` or `.tech-group`. Use a tolerance no larger than 0.5 CSS px for rounding. Also fail when the competency section overlaps the technology section or the technology section crosses the first-page boundary.

   ```javascript
   await page.emulateMedia({media: "print"});
   const layout = await page.evaluate(async () => {
     await document.fonts.ready;
     const tolerance = 0.5;
     const labels = document.querySelectorAll(".competency-heading, .tech-label");
     const labelFailures = [...labels].flatMap(label => {
       const range = document.createRange();
       range.selectNodeContents(label);
       const painted = range.getBoundingClientRect();
       const assigned = label.getBoundingClientRect();
       const group = label.closest(".competency-group, .tech-group").getBoundingClientRect();
       const horizontal = painted.right > assigned.right + tolerance ||
         label.scrollWidth > label.clientWidth + tolerance;
       const vertical = painted.bottom > group.bottom + tolerance;
       return horizontal || vertical ? [{text: label.textContent.trim(), horizontal, vertical}] : [];
     });
     const competencies = document.querySelector(".competencies-section").getBoundingClientRect();
     const technology = document.querySelector(".technology-section").getBoundingClientRect();
     const page1 = document.querySelector(".page-1").getBoundingClientRect();
     const sectionFailures = [];
     if (competencies.bottom > technology.top + tolerance) sectionFailures.push("section overlap");
     if (technology.bottom > page1.bottom + tolerance) sectionFailures.push("page-1 boundary");
     return {labelFailures, sectionFailures};
   });
   if (layout.labelFailures.length || layout.sectionFailures.length) {
     throw new Error(`CV layout overflow: ${JSON.stringify(layout)}`);
   }
   ```

   Treat this as a separate validation axis from ATS and PDF/UA: text clipped by CSS can remain extractable and still pass ATS. Do not add `overflow: hidden`, `text-overflow`, clipping, or masking to make an overflowing label appear valid. Shorten or rephrase the application-specific label, or correct the layout and then rerun the guard, PDF/UA, ATS, and visual inspection.

   **Done:** all competency and technology labels fit their assigned regions, the two sections do not collide, and the first-page content remains inside the page.

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

- `narrative.yaml` owns identity, headings, languages, education, employment, and default content. The override may change `subtitle`, allowed section items, sparse employment patches by `period`, `cover_letter`, and the documented application-specific `layout` correction.
- `projects.yaml.items` is the sole source for `project_overview.items`; use it only for contract-focused applications and in the narrative language. `projects.yaml.narrative_references` supports tailoring and does not supply rendered CV projects.
- Use plain YAML and evidence-led wording. Include only secured credentials, responsibilities, metrics, technologies, language levels, dates, employers, and outcomes.
- Put selected projects from page 2 onward; career history follows their final page. Put `project_overview`, when used, from page 4 onward.
- Keep the CV's first page within its supported competency and technology content. Keep cover letters to one A4 page using normal hyphens.
- Preserve the first-page design system in both photo variants: the dark 64.77 mm rail remains on the left, the main timeline geometry remains unchanged, and a no-photo profile begins no higher than the `competencies` heading.
- Keep timeline spacing and connector length coupled. If vertical gaps between competency, technology, or project groups change, update and visually verify the corresponding connector so every line passes continuously through its dots.
- When the final item under `KERNKOMPETENZEN` collides with the `TECHNOLOGIE STACK` heading, or technology groups collide with the page boundary, use the application-specific `layout: {page1_group_spacing: compact}` override before cutting supported content. Compact spacing is a collision correction, not a default: re-render page 1 and verify clear section separation, readable group spacing, and continuous timeline connectors through every dot.
- Use four competency groups when the secured evidence supports four distinct, role-relevant themes and the first page validates; do not create a fourth theme by duplicating or inventing claims.
- Render every final variant and inspect pages 1 and 2 visually in addition to the automated layout guard, PDF/UA, and ATS validation. Page 1 should use its vertical space without oversized technology gaps; page 2 should distribute selected projects evenly without forcing content onto the career-history page.

## Handoff

Retain the override YAML, evidence ledger, and company-research note in `agents/skills/application-generator/output/`. Hand off the validated PDF and, when useful, its HTML and validation JSON.
