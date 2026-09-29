"""Core abstractions for the independent-validation framework.

The project's headline numbers are each derived three separate ways: by the
MySQL pipeline, by a second SQL path against the base tables, and by this
package reading the original CSVs with pandas. Three independent derivations
agreeing is a much stronger claim than any single computation.

This module defines the vocabulary that makes that repeatable:

    Expectation       a value the project reported, and how far a
                      re-derivation may legitimately drift from it
    ValidationResult  one comparison, with timing
    Check             an abstract re-derivation; subclasses supply `measure`
    ValidationSuite   an ordered collection of checks
    SuiteReport       the outcome, queryable rather than printed
"""

from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TYPE_CHECKING, Callable, Iterator, Sequence

if TYPE_CHECKING:  # avoids a circular import at runtime
    from .dataset import Dataset


@dataclass(frozen=True)
class Expectation:
    """A number the project published, plus an allowed tolerance.

    Counts are exact (tolerance 0). Money and rates carry a tolerance because
    they are reported rounded - card exposure is quoted to one decimal place in
    millions, so a re-derivation may differ in the last digit without being
    wrong.
    """

    value: float
    tolerance: float = 0.0

    def agrees_with(self, actual: float) -> bool:
        return abs(actual - self.value) <= self.tolerance


@dataclass(frozen=True)
class ValidationResult:
    """The outcome of one check against one data source."""

    check_name: str
    source_name: str
    expectation: Expectation
    actual: float
    seconds: float

    @property
    def passed(self) -> bool:
        return self.expectation.agrees_with(self.actual)

    @property
    def delta(self) -> float:
        return self.actual - self.expectation.value

    def __str__(self) -> str:
        verdict = "PASS" if self.passed else "FAIL"
        return (f"{verdict}  {self.check_name}: "
                f"expected {self.expectation.value:,}, got {self.actual:,}")


class Check(ABC):
    """One independently re-derived number and the value it must reproduce.

    Subclasses implement `measure`. Note that the expected value lives *on the
    check* rather than in a separate lookup table. That is the main structural
    improvement over the procedural script this replaces: there, adding a check
    meant editing a dictionary, a call site and a print statement, and the
    dictionary could silently drift out of step with the code. Here a check is
    one object that knows its own name, its own expectation and how to derive
    its own value.
    """

    def __init__(self, name: str, expectation: Expectation) -> None:
        self.name = name
        self.expectation = expectation

    @abstractmethod
    def measure(self, dataset: "Dataset") -> float:
        """Re-derive the number from source data. Implemented by subclasses."""

    def run(self, dataset: "Dataset") -> ValidationResult:
        """Template method: time the measurement and wrap it in a result."""
        started = time.perf_counter()
        actual = self.measure(dataset)
        elapsed = time.perf_counter() - started
        return ValidationResult(
            check_name=self.name,
            source_name=dataset.name,
            expectation=self.expectation,
            actual=float(actual),
            seconds=elapsed,
        )

    def __repr__(self) -> str:
        return (f"{type(self).__name__}(name={self.name!r}, "
                f"expect={self.expectation.value:,})")


class ValidationSuite:
    """An ordered, runnable collection of checks."""

    def __init__(self, name: str) -> None:
        self.name = name
        self._checks: list[Check] = []

    def add(self, *checks: Check) -> "ValidationSuite":
        """Register checks. Returns self so registration can be chained."""
        self._checks.extend(checks)
        return self

    def run(self, dataset: "Dataset",
            observer: Callable[[ValidationResult], None] | None = None) -> "SuiteReport":
        """Run every check against `dataset`.

        `observer` is called after each result, which lets a reporter stream
        progress without the suite knowing anything about output formatting.
        """
        results: list[ValidationResult] = []
        for check in self._checks:
            result = check.run(dataset)
            results.append(result)
            if observer is not None:
                observer(result)
        return SuiteReport(self.name, dataset.name, tuple(results))

    def __len__(self) -> int:
        return len(self._checks)

    def __iter__(self) -> Iterator[Check]:
        return iter(self._checks)

    def __repr__(self) -> str:
        return f"ValidationSuite({self.name!r}, {len(self)} checks)"


@dataclass(frozen=True)
class SuiteReport:
    """The result of a suite run - queryable, not merely printed."""

    suite_name: str
    source_name: str
    results: Sequence[ValidationResult]

    @property
    def passed(self) -> tuple[ValidationResult, ...]:
        return tuple(r for r in self.results if r.passed)

    @property
    def failed(self) -> tuple[ValidationResult, ...]:
        return tuple(r for r in self.results if not r.passed)

    @property
    def all_passed(self) -> bool:
        return not self.failed

    @property
    def seconds(self) -> float:
        return sum(r.seconds for r in self.results)

    @property
    def exit_code(self) -> int:
        """0 when everything reconciles - so this can gate a CI pipeline."""
        return 0 if self.all_passed else 1
