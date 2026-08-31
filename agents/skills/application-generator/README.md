# CV renderer

The renderer produces a semantic PDF/UA-1 CV from a schema-version-3
`narrative.yaml` baseline and a deliberately small YAML override. Both inputs
are required and their top-level `language` values must match.

```powershell
python scripts/render_cv.py `
  --narrative ..\..\..\secrets\cv\narrative.yaml `
  --input agents\skills\application-generator\examples\permanent-role.yaml `
  --output C:\path\cv.pdf
```

`narrative.yaml` owns identity, the secured default photo, contact details, languages, education,
employment, every visible heading, and the default section content. The input
may override `subtitle` and atomically replace `profile.items`, `competencies.items`,
`technology.items`, `selected_projects.items`, or `project_overview.items`.
Section headings always remain baseline-only.
It may sparsely patch employment records by `period`, changing only `title`
and `points`. Set top-level `photo: null` to render the supported no-photo
layout; omit the field to retain the secured narrative portrait. Any non-null
photo override and all other protected sections fail.

All collections are YAML lists: a section uses `items` and nested list content
uses `points`. `profile.items` renders as paragraphs; all other `points` render
as bullet lists. `selected_projects` must contain content after merging.
`project_overview` is optional, additive, begins on page 4, and can continue
onto subsequent pages. When it is present, the renderer reads `projects.yaml`
beside the narrative (or an explicit `--projects` path) and rejects a different
`language`.

Run standalone ATS validation with the same source pair:

```powershell
python scripts/validate_ats.py --narrative ..\..\..\secrets\cv\narrative.yaml --input override.yaml --pdf C:\path\cv.pdf
```
