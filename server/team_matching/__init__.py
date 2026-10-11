"""Versioned questionnaire and pure rule matching; no database or HTTP imports."""
from .engine import CONFIG, validate_answers, validate_requirements, match_team
