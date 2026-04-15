---
name: review-plans
description: 'Review implementation plans, find gaps/risks, ask targeted clarifying questions with vscode_askQuestions, then update the plan file from user answers. Use for: review this plan, tighten plan, quality-gate plan, plan critique, plan refinement.'
argument-hint: 'Provide plan file path, review focus, and constraints (tasks/tools/scope).'
user-invocable: true
---

# Review Plans

## When to Use
- User says review this plan, critique plan, refine plan, or quality-check plan.
- Plan needs concrete pass/fail checks, reduced ambiguity, and executable steps.
- User wants question-driven refinement before editing.

## Outcome
- Severity-ordered findings with concrete fixes.
- Small set of targeted clarifying questions via `vscode_askQuestions`.
- Updated plan reflecting user answers.
- Brief residual-risk summary.

## Procedure
1. Read current plan file from workspace.
2. Extract workflow skeleton:
- objective
- ordered steps
- decision points/branches
- verification gates
- constraints
3. Review plan with code-review mindset. Prioritize:
- behavioral regressions
- invalid assumptions
- unverifiable acceptance criteria
- missing failure handling
- tool/process constraint violations
4. Report findings ordered by severity with file/line references.
5. Ask all high-impact unresolved questions using `vscode_askQuestions`.
- No hard question cap. If 10 high-impact questions exist, ask all 10.
- Use fixed options when possible.
- Questions must directly change plan text.
6. Update plan file based on answers.
- Preserve style/voice unless user asked to rewrite style.
- Apply minimal delta edits.
7. Re-check updated plan for internal consistency.
8. Return:
- what changed
- why changed
- remaining risks (if any)

## Decision Rules
- If acceptance metric ambiguous, ask for single authority metric.
- If runtime validation path can be stale/non-deterministic, add explicit validity gate unless user declines.
- If stop/complete criteria are vague, convert to measurable windowed checks.
- If constraints conflict (tasks/tools/scope), prefer user hard constraints and mark residual risk.
- If no material findings, state no findings and list residual testing gaps.
- If user runs caveman mode, match requested caveman intensity for review/update text.
- After clarifications resolved, auto-patch plan file by default unless user explicitly asks for review-only.

## Quality Gates
- Each pass criterion observable in logs/output.
- Each fail criterion explicit.
- Every "hold" or "stable" claim has time or sample window.
- Clamp/saturation policy explicit when speed/limits involved.
- Scope boundaries explicit (in-scope/out-scope).
- Regression protections explicit (contracts/names/interfaces unchanged).

## Output Format
1. Findings first (severity-ordered).
2. Questions asked (or state none needed).
3. Plan updates applied.
4. Residual risks.

## Example Triggers
- /review-plans untitled:plan-x.prompt.md
- Review this plan and tighten acceptance checks.
- Ask me questions, then patch plan.

## Notes
- Use `vscode_askQuestions` for clarifications instead of open-ended chat prompts when possible.
- Keep edits minimal and local to plan file.
- Do not expand scope beyond user-requested workflow unless needed for correctness.
- Default tone: concise normal. Switch to caveman terse when active/requested.
