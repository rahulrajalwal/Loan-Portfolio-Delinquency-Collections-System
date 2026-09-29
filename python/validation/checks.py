"""Concrete checks.

Each class re-derives one published number. Six measurement strategies are
represented; the `BookCheck` family additionally shares an expensive setup step
through a template method, so that building 'the book' - one row per account at
its latest observed month, across two files totalling 13.8 million rows -
happens once rather than four times.
"""

from __future__ import annotations

from typing import Sequence

import pandas as pd

from .core import Check, Expectation
from .dataset import BucketScheme, Dataset


class RowCountCheck(Check):
    """Number of rows in a file."""

    def __init__(self, name: str, expectation: Expectation,
                 filename: str, column: str) -> None:
        super().__init__(name, expectation)
        self.filename = filename
        self.column = column

    def measure(self, dataset: Dataset) -> float:
        return len(dataset.frame(self.filename, [self.column]))


class ColumnSumCheck(Check):
    """Sum of a column, optionally scaled (e.g. to millions)."""

    def __init__(self, name: str, expectation: Expectation, filename: str,
                 column: str, scale: float = 1.0, decimals: int | None = None) -> None:
        super().__init__(name, expectation)
        self.filename = filename
        self.column = column
        self.scale = scale
        self.decimals = decimals

    def measure(self, dataset: Dataset) -> float:
        total = dataset.frame(self.filename, [self.column])[self.column].sum() / self.scale
        return round(total, self.decimals) if self.decimals is not None else total


class ColumnMeanCheck(Check):
    """Mean of a column, scaled - used for the 8.0729% default base rate."""

    def __init__(self, name: str, expectation: Expectation, filename: str,
                 column: str, scale: float = 1.0, decimals: int = 4) -> None:
        super().__init__(name, expectation)
        self.filename = filename
        self.column = column
        self.scale = scale
        self.decimals = decimals

    def measure(self, dataset: Dataset) -> float:
        mean = dataset.frame(self.filename, [self.column])[self.column].mean()
        return round(mean * self.scale, self.decimals)


class DuplicateKeyCheck(Check):
    """Rows sharing a key that was documented as unique.

    This is the check that overturned the dataset's own documentation. The
    payment table was described as one row per installment; the key is not
    unique, and investigation showed one row is a payment *event* - 653,483
    installments were settled by two or more payments, one by twelve.
    """

    def __init__(self, name: str, expectation: Expectation,
                 filename: str, key_columns: Sequence[str]) -> None:
        super().__init__(name, expectation)
        self.filename = filename
        self.key_columns = list(key_columns)

    def measure(self, dataset: Dataset) -> float:
        df = dataset.frame(self.filename, self.key_columns)
        return len(df) - len(df.drop_duplicates())


# ---------------------------------------------------------------------------
# The book: one row per account at its latest observed month, across products.
# Four checks share that setup, so it lives in a base class and each subclass
# supplies only the metric it needs.
# ---------------------------------------------------------------------------

class BookCheck(Check):
    """Template method: build the book once, then measure it."""

    POS_FILE = "POS_CASH_balance.csv"
    POS_COLS = ["SK_ID_PREV", "MONTHS_BALANCE", "NAME_CONTRACT_STATUS", "SK_DPD"]
    CARD_FILE = "credit_card_balance.csv"
    CARD_COLS = ["SK_ID_PREV", "MONTHS_BALANCE", "NAME_CONTRACT_STATUS",
                 "SK_DPD", "AMT_BALANCE"]
    ACTIVE = "Active"

    def measure(self, dataset: Dataset) -> float:
        pos = dataset.latest_per_account(self.POS_FILE, self.POS_COLS)
        card = dataset.latest_per_account(self.CARD_FILE, self.CARD_COLS)
        return self.metric(pos, card)

    def metric(self, pos: pd.DataFrame, card: pd.DataFrame) -> float:
        raise NotImplementedError


class AccountsAtLatestMonthCheck(BookCheck):
    """Every account that appears in either panel."""

    def metric(self, pos: pd.DataFrame, card: pd.DataFrame) -> float:
        return len(pos) + len(card)


class ActiveAccountsCheck(BookCheck):
    """Accounts still live at their last observation - the real book.

    Only about 31% of accounts qualify: POS loans run roughly ten months and
    then complete, so most have closed by the time the customer reappears.
    """

    def metric(self, pos: pd.DataFrame, card: pd.DataFrame) -> float:
        return int((pos.NAME_CONTRACT_STATUS == self.ACTIVE).sum()
                   + (card.NAME_CONTRACT_STATUS == self.ACTIVE).sum())


class DelinquentAccountsCheck(BookCheck):
    """Live accounts behind on payment - the collections queue."""

    def metric(self, pos: pd.DataFrame, card: pd.DataFrame) -> float:
        pos_d = (pos.NAME_CONTRACT_STATUS == self.ACTIVE) & (pos.SK_DPD > 0)
        card_d = (card.NAME_CONTRACT_STATUS == self.ACTIVE) & (card.SK_DPD > 0)
        return int(pos_d.sum() + card_d.sum())


class CardExposureCheck(BookCheck):
    """Outstanding balance on live cards, in millions.

    Card exposure is a real measured balance. The POS equivalent is a derived
    proxy and is deliberately not validated here - a number that is itself an
    assumption cannot be independently confirmed, only recomputed.
    """

    def metric(self, pos: pd.DataFrame, card: pd.DataFrame) -> float:
        live = card.loc[card.NAME_CONTRACT_STATUS == self.ACTIVE, "AMT_BALANCE"]
        return round(live.sum() / 1_000_000, 1)


class TransitionCountCheck(Check):
    """Month-to-month moves between two delinquency buckets.

    Reproduces one cell of the roll-rate matrix, including the guard that makes
    it correct: consecutive *rows* are not necessarily consecutive *months*.
    The panel has gaps, and without requiring the month index to advance by
    exactly one, a jump from month -8 to month -3 would be counted as a single
    month's transition - inventing movement that never happened.
    """

    def __init__(self, name: str, expectation: Expectation, filename: str,
                 scheme: BucketScheme, from_bucket: str, to_bucket: str,
                 group: str = "SK_ID_PREV", order: str = "MONTHS_BALANCE",
                 dpd_column: str = "SK_DPD") -> None:
        super().__init__(name, expectation)
        self.filename = filename
        self.scheme = scheme
        self.from_bucket = from_bucket
        self.to_bucket = to_bucket
        self.group = group
        self.order = order
        self.dpd_column = dpd_column

    def measure(self, dataset: Dataset) -> float:
        # sort_values returns a copy, so the cached frame is never mutated
        df = dataset.frame(
            self.filename, [self.group, self.order, self.dpd_column]
        ).sort_values([self.group, self.order])

        bucket = self.scheme.apply(df[self.dpd_column])
        previous_bucket = bucket.groupby(df[self.group]).shift(1)
        previous_month = df.groupby(self.group)[self.order].shift(1)

        consecutive = df[self.order] == previous_month + 1
        moved = (previous_bucket == self.from_bucket) & (bucket == self.to_bucket)
        return int((moved & consecutive).sum())
