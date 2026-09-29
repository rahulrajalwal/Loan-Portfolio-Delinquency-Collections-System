"""Independent validation of the project's published figures.

Every headline number in this project is derived three separate ways:

    CSV -> MySQL -> staging -> mart -> reported number     the pipeline
    CSV -> MySQL, a different query                        SQL cross-check
    CSV -> pandas                                          this package

Different engine, different language, different code, same source files. If
all three agree, the number is trustworthy in a way no single computation is.

Typical use::

    from validation import Dataset, ValidationSuite, ConsoleReporter
    from validation.checks import RowCountCheck
    from validation.core import Expectation

    suite = ValidationSuite("my suite").add(
        RowCountCheck("train customers", Expectation(307_511),
                      "application_train.csv", "SK_ID_CURR"),
    )
    reporter = ConsoleReporter()
    report = suite.run(Dataset("data/raw"), observer=reporter.result)
    reporter.summary(report)
    raise SystemExit(report.exit_code)
"""

from .core import (
    Check,
    Expectation,
    SuiteReport,
    ValidationResult,
    ValidationSuite,
)
from .dataset import ANALYTICAL, REPORTING, BucketScheme, Dataset
from .reporting import ConsoleReporter, JsonReporter

__all__ = [
    "Check",
    "Expectation",
    "SuiteReport",
    "ValidationResult",
    "ValidationSuite",
    "Dataset",
    "BucketScheme",
    "REPORTING",
    "ANALYTICAL",
    "ConsoleReporter",
    "JsonReporter",
]

__version__ = "1.0.0"
