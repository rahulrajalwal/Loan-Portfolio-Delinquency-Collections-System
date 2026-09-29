"""
PHASE 11B - INDEPENDENT VALIDATION

Re-derives the project's headline numbers from the ORIGINAL CSVs using pandas,
as a third path entirely separate from the MySQL pipeline:

    CSV -> MySQL base tables -> staging -> mart -> reported number   (pipeline)
    CSV -> MySQL base tables, a different query                      (SQL check)
    CSV -> pandas                                                    (THIS FILE)

If all three agree, the number is trustworthy in a way that no single
computation can be. Everything after Phase 6 reads from the mart, so a single
error while building it would otherwise propagate silently through five phases.

Run:
    python python/validate_independent.py
    python python/validate_independent.py --json report.json
    python python/validate_independent.py --data-root path/to/csvs

Exits 0 when every figure reconciles, 1 otherwise - so it can gate a pipeline.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from validation import (
    ANALYTICAL,
    ConsoleReporter,
    Dataset,
    Expectation,
    JsonReporter,
    ValidationSuite,
)
from validation.checks import (
    AccountsAtLatestMonthCheck,
    ActiveAccountsCheck,
    CardExposureCheck,
    ColumnMeanCheck,
    ColumnSumCheck,
    DelinquentAccountsCheck,
    DuplicateKeyCheck,
    RowCountCheck,
    TransitionCountCheck,
)

DEFAULT_DATA_ROOT = Path(__file__).resolve().parent.parent / "data" / "raw"


def build_suite() -> ValidationSuite:
    """Declare every figure this project publishes, and how to re-derive it.

    Counts use a zero tolerance: they must reproduce exactly. Card exposure
    allows 0.1 because it is quoted to one decimal place in millions, and the
    default rate allows 0.0001 because it is quoted to four.
    """
    return ValidationSuite("PHASE 11B - INDEPENDENT VALIDATION").add(

        # --- the observed outcome, against which every signal is measured ---
        RowCountCheck(
            "train customers", Expectation(307_511),
            "application_train.csv", "SK_ID_CURR"),
        ColumnSumCheck(
            "defaults", Expectation(24_825),
            "application_train.csv", "TARGET"),
        ColumnMeanCheck(
            "TARGET base rate %", Expectation(8.0729, tolerance=0.0001),
            "application_train.csv", "TARGET", scale=100, decimals=4),

        # --- the grain finding that overturned the documentation ---
        DuplicateKeyCheck(
            "split payments (F1)", Expectation(653_483),
            "installments_payments.csv",
            ["SK_ID_PREV", "NUM_INSTALMENT_VERSION", "NUM_INSTALMENT_NUMBER"]),

        # --- the book: shared setup, four metrics ---
        AccountsAtLatestMonthCheck(
            "accounts at latest month", Expectation(1_040_632)),
        ActiveAccountsCheck(
            "active accounts", Expectation(327_101)),
        DelinquentAccountsCheck(
            "delinquent active (queue size)", Expectation(7_211)),
        CardExposureCheck(
            "CARD exposure (millions)", Expectation(7_774.0, tolerance=0.1)),

        # --- one cell of the roll-rate matrix, with the gap guard ---
        TransitionCountCheck(
            "POS 1-30 -> 31-90 transitions", Expectation(7_291),
            "POS_CASH_balance.csv", ANALYTICAL,
            from_bucket="1-30", to_bucket="31-90"),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT,
                        help="directory holding the raw Kaggle CSVs")
    parser.add_argument("--json", type=str, default=None,
                        help="also write a machine-readable report here")
    args = parser.parse_args()

    dataset = Dataset(args.data_root)
    suite = build_suite()
    reporter = ConsoleReporter()

    reporter.header(suite.name, dataset.name, len(suite))
    report = suite.run(dataset, observer=reporter.result)
    reporter.summary(report)

    if args.json:
        JsonReporter(args.json).write(report)
        print(f"report written to {args.json}")

    return report.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
