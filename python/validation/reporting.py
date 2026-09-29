"""Output formatting.

Kept separate from the suite so that running checks and displaying them are
independent concerns: the suite emits `ValidationResult` objects and knows
nothing about terminals, and a reporter renders them without knowing how they
were produced. Adding a JSON or JUnit reporter for CI means writing one class,
not touching the checks.
"""

from __future__ import annotations

import json
import sys
from typing import TextIO

from .core import SuiteReport, ValidationResult


class ConsoleReporter:
    """Streams results to a terminal as they complete."""

    def __init__(self, stream: TextIO | None = None, width: int = 92) -> None:
        self.stream = stream or sys.stdout
        self.width = width

    def _line(self, char: str = "=") -> None:
        print(char * self.width, file=self.stream)

    def header(self, suite_name: str, source_name: str, n_checks: int) -> None:
        self._line()
        print(f"{suite_name}  ({n_checks} checks against {source_name})",
              file=self.stream)
        self._line()

    def result(self, result: ValidationResult) -> None:
        """Observer callback - called by the suite after each check."""
        verdict = "PASS" if result.passed else "FAIL"
        print(
            f"  {verdict}  {result.check_name:<36}"
            f"expected={result.expectation.value:>13,}"
            f"  actual={result.actual:>13,}"
            f"  {result.seconds:>6.1f}s",
            file=self.stream,
        )

    def summary(self, report: SuiteReport) -> None:
        self._line()
        print(f"RESULT: {len(report.passed)} of {len(report.results)} checks passed "
              f"in {report.seconds:.1f}s", file=self.stream)
        if report.failed:
            print("\nFAILURES:", file=self.stream)
            for r in report.failed:
                print(f"  {r.check_name}: expected {r.expectation.value:,}, "
                      f"got {r.actual:,}, delta {r.delta:+,}", file=self.stream)
        self._line()


class JsonReporter:
    """Writes a machine-readable report - for CI, or to diff two runs."""

    def __init__(self, path: str) -> None:
        self.path = path

    def write(self, report: SuiteReport) -> None:
        payload = {
            "suite": report.suite_name,
            "source": report.source_name,
            "all_passed": report.all_passed,
            "seconds": round(report.seconds, 2),
            "results": [
                {
                    "check": r.check_name,
                    "expected": r.expectation.value,
                    "actual": r.actual,
                    "tolerance": r.expectation.tolerance,
                    "passed": r.passed,
                    "delta": r.delta,
                    "seconds": round(r.seconds, 3),
                }
                for r in report.results
            ],
        }
        with open(self.path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
