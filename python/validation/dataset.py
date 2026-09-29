"""Source-data access and the delinquency bucket scheme.

`Dataset` is deliberately a concrete class rather than an abstract base. There
is exactly one source of truth for this validation - the CSV files Kaggle
published - and defining an interface for a single implementation is
speculative generality. If a second real source ever appears, extracting an
ABC is a two-minute refactor; inventing one now would be a guess about a
future that may not arrive.

`BucketScheme`, by contrast, genuinely earns being an object: the project runs
two different schemes for two different purposes.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class BucketScheme:
    """Maps days-past-due to a delinquency bucket.

    Two instances exist below because the project needs two:

    REPORTING   follows RBI SMA/NPA boundaries (SMA-0, SMA-1, SMA-2, NPA) and
                is used for portfolio reporting, where comparability with a
                recognised convention matters.

    ANALYTICAL  merges 31-60 and 61-90 into a single 31-90 band. Measurement
                forced this: only 542 accounts in the entire book ever peak in
                the 61-90 range, which is far too thin to support a stable
                transition rate. Roll-rate analysis uses this scheme.

    Both split 90+ at 360 days, because accounts beyond a year past due are
    written-off balances with a still-running counter - 1,369 of them holding a
    mean balance of 179 - and merging them with genuinely collectable 90-day
    accounts would destroy the signal.
    """

    name: str
    upper_bounds: tuple[float, ...]   # inclusive upper edge of each bucket
    labels: tuple[str, ...]           # one more label than bounds (final catch-all)

    def __post_init__(self) -> None:
        if len(self.labels) != len(self.upper_bounds) + 1:
            raise ValueError(
                f"{self.name}: expected {len(self.upper_bounds) + 1} labels, "
                f"got {len(self.labels)}"
            )

    def label_of(self, dpd: float) -> str:
        """Bucket a single days-past-due value."""
        for bound, label in zip(self.upper_bounds, self.labels):
            if dpd <= bound:
                return label
        return self.labels[-1]

    def apply(self, dpd: pd.Series) -> pd.Series:
        """Bucket a whole column.

        Uses pd.cut rather than .map(label_of): on a 10-million-row column the
        element-wise version takes minutes, the vectorised one takes seconds.
        """
        edges = [-np.inf, *self.upper_bounds, np.inf]
        return pd.cut(dpd, bins=edges, labels=list(self.labels), right=True)

    def __repr__(self) -> str:
        return f"BucketScheme({self.name!r}, {len(self.labels)} buckets)"


REPORTING = BucketScheme(
    name="RBI-aligned reporting",
    upper_bounds=(0, 30, 60, 90, 360),
    labels=("0-current", "1-30", "31-60", "61-90", "91-360", "360+"),
)

ANALYTICAL = BucketScheme(
    name="analytical (sparse middle merged)",
    upper_bounds=(0, 30, 90, 360),
    labels=("0-current", "1-30", "31-90", "91-360", "360+"),
)


class Dataset:
    """Lazy, cached access to the raw Kaggle CSVs.

    Frames are read once per (file, column-set) and reused. The procedural
    version this replaces re-read the 392 MB POS file for its roll-rate check
    after already loading it for the book checks; caching removes that class of
    waste as more checks are added.

    Memory note: the cache is bounded by what callers request, not by file
    size. Only the columns a check actually needs are read, which is what keeps
    a 58-million-row dataset inside 7.3 GB of RAM. Call `clear()` to release.
    """

    def __init__(self, root: str | Path, name: str = "Kaggle CSV") -> None:
        self.root = Path(root)
        self.name = name
        self._frames: dict[tuple[str, tuple[str, ...]], pd.DataFrame] = {}
        self._latest: dict[tuple[str, tuple[str, ...]], pd.DataFrame] = {}

    def frame(self, filename: str, columns: Sequence[str]) -> pd.DataFrame:
        """Return the named columns of a CSV, reading it at most once.

        The returned frame is the cached object. Callers must not mutate it -
        derive a copy instead. Checks in this package follow that rule.
        """
        key = (filename, tuple(columns))
        if key not in self._frames:
            path = self.root / filename
            if not path.exists():
                raise FileNotFoundError(
                    f"{path} not found. The raw CSVs are not in the repository - "
                    f"see the 'Getting the data' section of README.md."
                )
            self._frames[key] = pd.read_csv(path, usecols=list(columns))
        return self._frames[key]

    def latest_per_account(
        self,
        filename: str,
        columns: Sequence[str],
        group: str = "SK_ID_PREV",
        order: str = "MONTHS_BALANCE",
    ) -> pd.DataFrame:
        """One row per account: its most recent observed month.

        This is 'the book' - every account as it stood at its last observation.
        Because the dataset holds no calendar dates, that observation point is
        relative to each customer's own application rather than a common as-of
        date, and the project states this wherever the figure is used.
        """
        key = (filename, tuple(columns))
        if key not in self._latest:
            df = self.frame(filename, columns)
            self._latest[key] = df.loc[df.groupby(group)[order].idxmax()]
        return self._latest[key]

    def clear(self) -> None:
        """Release every cached frame."""
        self._frames.clear()
        self._latest.clear()

    @property
    def cached_rows(self) -> int:
        return sum(len(df) for df in self._frames.values())

    def __repr__(self) -> str:
        return (f"Dataset(root={str(self.root)!r}, "
                f"cached={len(self._frames)} frames / {self.cached_rows:,} rows)")
