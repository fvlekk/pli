# Pli backend

## Map
- **Routes:** `src/pli/main.py` — `GET /healthz`, `POST /v1/extractions` (ID token + App Check `auth.py`, rate limit per uid, IP and
  instance `limiteur.py`, PDF page cap `courrier.py`).
- **Business logic:** `src/pli/extracteurs/` (`regle.py` offline baseline, `claude.py`, `base.py`) · `schema.py` (output +
  text limits) · `courrier.py` (letter input) · `journal.py` (logs without content).
- **Tests:** `tests/test_*.py` (pytest) · `evals/` (`run.py`, `dataset/`, `attendu.jsonl`).

## Commands
```bash
uv sync && uv run ruff check . && uv run ruff format --check . && uv run pytest
uv run python -m evals.run --extracteur regle            # offline, free
uv run python -m evals.run --extracteur claude --split test   # needs ANTHROPIC_API_KEY, costs money: ask first
```
The App Check token is required unless `PLI_APP_CHECK=0` (then only checked and logged, `app_check: ...`).

## Conventions
Small modules, pydantic models at the edges, dependencies injected (tests use fakes, never the network).
