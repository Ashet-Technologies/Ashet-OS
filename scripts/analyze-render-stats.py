#!/usr/bin/env python3

from __future__ import annotations

import argparse
import math
import re
import statistics
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*m")
RENDER_START_RE = re.compile(r"graphics:\s+(?P<renderer>[a-z_]+) render of (?P<size>\d+) bytes:")
VALUE_RE = re.compile(r"=\s*(\d+)")
XIP_RE = re.compile(r"XIP Stats\s*=\s*(\d+)\s*\(hits:\s*(\d+),\s*misses:\s*(\d+)\)")
PERF_RE = re.compile(r"PERF(?P<index>[0-3])\[(?P<name>[^\]]+)\]\s*=\s*(?P<value>\d+)")

BASELINE_RENDERER = "linear_sync"
RENDERER_ORDER = {
    "linear_async": 0,
    "linear_sync": 1,
    "tiled_async": 2,
    "tiled_sync": 3,
}
PRIMARY_METRIC_ORDER = {
    "cycles": 0,
    "duration_us": 1,
    "xip_total": 2,
    "xip_misses": 3,
}
STAT_FIELDS = ("min", "max", "mean", "average", "median", "stdev")


@dataclass(frozen=True)
class RenderRecord:
    renderer: str
    command_size: int
    metrics: dict[str, float]


@dataclass(frozen=True)
class SummaryStats:
    min: float
    max: float
    mean: float
    median: float
    stdev: float

    @classmethod
    def from_values(cls, values: list[float]) -> "SummaryStats":
        if not values:
            raise ValueError("summary requires at least one value")

        stdev = statistics.stdev(values) if len(values) > 1 else 0.0
        return cls(
            min=min(values),
            max=max(values),
            mean=statistics.fmean(values),
            median=statistics.median(values),
            stdev=stdev,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyze renderer performance dumps from an ashet log.",
    )
    parser.add_argument(
        "logfile",
        nargs="?",
        default="/tmp/ashet.log",
        help="Path to the log file to analyze. Defaults to /tmp/ashet.log.",
    )
    parser.add_argument(
        "-s",
        "--size",
        type=int,
        metavar="BYTES",
        help="Only include render dumps with this exact command size in bytes.",
    )
    return parser.parse_args()


def strip_ansi(text: str) -> str:
    return ANSI_ESCAPE_RE.sub("", text)


def parse_render_records(log_path: Path) -> list[RenderRecord]:
    records: list[RenderRecord] = []

    current_renderer: str | None = None
    current_size: int | None = None
    current_metrics: dict[str, float] | None = None

    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = strip_ansi(raw_line).strip()

            start_match = RENDER_START_RE.search(line)
            if start_match:
                current_renderer = start_match.group("renderer")
                current_size = int(start_match.group("size"))
                current_metrics = {}
                continue

            if current_metrics is None:
                continue

            if "Cycles" in line:
                current_metrics["cycles"] = parse_scalar_value(line)
                continue

            if "Duration" in line:
                current_metrics["duration_us"] = parse_scalar_value(line)
                continue

            if "XIP Stats" in line:
                match = XIP_RE.search(line)
                if match is None:
                    raise ValueError(f"failed to parse XIP stats line: {line}")
                current_metrics["xip_total"] = float(match.group(1))
                current_metrics["xip_misses"] = float(match.group(3))
                continue

            perf_match = PERF_RE.search(line)
            if perf_match:
                metric_name = perf_match.group("name")
                current_metrics[metric_name] = float(perf_match.group("value"))

                if perf_match.group("index") == "3":
                    if current_renderer is None or current_size is None:
                        raise AssertionError("parser lost render block state")
                    records.append(
                        RenderRecord(
                            renderer=current_renderer,
                            command_size=current_size,
                            metrics=current_metrics,
                        )
                    )
                    current_renderer = None
                    current_size = None
                    current_metrics = None

    return records


def parse_scalar_value(line: str) -> float:
    match = VALUE_RE.search(line)
    if match is None:
        raise ValueError(f"failed to parse scalar line: {line}")
    return float(match.group(1))


def build_grouped_values(records: list[RenderRecord]) -> dict[str, dict[str, list[float]]]:
    grouped: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))

    for record in records:
        for metric_name, value in record.metrics.items():
            grouped[record.renderer][metric_name].append(value)

    return grouped


def summarize_metric(values: list[float]) -> SummaryStats:
    return SummaryStats.from_values(values)


def format_value(value: float) -> str:
    if math.isfinite(value) and value.is_integer():
        return f"{int(value)}"
    return f"{value:.3f}"


def format_abs_delta(value: float, baseline: float) -> str:
    delta = value - baseline
    sign = "+" if delta >= 0 else ""
    return f"{sign}{format_value(delta)}"


def format_ratio(value: float, baseline: float) -> str:
    if baseline == 0:
        return "n/a"
    return f"{(value / baseline) * 100:.2f}%"


def renderer_sort_key(renderer: str) -> tuple[int, str]:
    return (RENDERER_ORDER.get(renderer, 999), renderer)


def print_section_title(title: str) -> None:
    print(title)
    print("=" * len(title))


def metric_sort_key(metric_name: str) -> tuple[int, str]:
    return (PRIMARY_METRIC_ORDER.get(metric_name, 100), metric_name)


def summarize_renderer_metrics(grouped: dict[str, dict[str, list[float]]]) -> dict[str, dict[str, SummaryStats]]:
    return {
        renderer: {
            metric_name: summarize_metric(values)
            for metric_name, values in metrics.items()
        }
        for renderer, metrics in grouped.items()
    }


def stat_value(summary: SummaryStats, field_name: str) -> float:
    if field_name == "average":
        return summary.mean
    return getattr(summary, field_name)


def render_table(headers: list[str], rows: list[list[str]]) -> str:
    widths = [len(header) for header in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def format_row(row: list[str]) -> str:
        return "  ".join(cell.rjust(widths[index]) if index > 0 else cell.ljust(widths[index]) for index, cell in enumerate(row))

    lines = [format_row(headers), format_row(["-" * width for width in widths])]
    lines.extend(format_row(row) for row in rows)
    return "\n".join(lines)


def build_value_rows(metric_summaries: dict[str, SummaryStats]) -> list[list[str]]:
    rows: list[list[str]] = []
    for metric_name in sorted(metric_summaries, key=metric_sort_key):
        summary = metric_summaries[metric_name]
        rows.append(
            [metric_name] + [format_value(stat_value(summary, field_name)) for field_name in STAT_FIELDS]
        )
    return rows


def build_delta_rows(
    metric_summaries: dict[str, SummaryStats],
    baseline_summaries: dict[str, SummaryStats],
    relative_only: bool,
) -> list[list[str]]:
    rows: list[list[str]] = []
    metric_names = sorted(metric_summaries, key=metric_sort_key)
    for metric_name in metric_names:
        summary = metric_summaries[metric_name]
        baseline_summary = baseline_summaries.get(metric_name)
        if baseline_summary is None:
            rows.append([metric_name] + ["n/a" for _ in STAT_FIELDS])
            continue

        if relative_only:
            cells = [
                format_ratio(stat_value(summary, field_name), stat_value(baseline_summary, field_name))
                for field_name in STAT_FIELDS
            ]
        else:
            cells = [
                format_abs_delta(stat_value(summary, field_name), stat_value(baseline_summary, field_name))
                for field_name in STAT_FIELDS
            ]
        rows.append([metric_name] + cells)
    return rows


def print_renderer_report(summaries: dict[str, dict[str, SummaryStats]]) -> None:
    renderers = sorted(summaries, key=renderer_sort_key)
    baseline_summaries = summaries.get(BASELINE_RENDERER)

    for renderer in renderers:
        print_section_title(f"Renderer: {renderer}")
        print("Raw Statistics")
        print(
            render_table(
                ["metric", *STAT_FIELDS],
                build_value_rows(summaries[renderer]),
            )
        )

        if baseline_summaries is not None:
            print()
            print(f"Absolute Delta Vs {BASELINE_RENDERER}")
            print(
                render_table(
                    ["metric", *STAT_FIELDS],
                    build_delta_rows(summaries[renderer], baseline_summaries, relative_only=False),
                )
            )
            print()
            print(f"Relative Vs {BASELINE_RENDERER} (100% baseline)")
            print(
                render_table(
                    ["metric", *STAT_FIELDS],
                    build_delta_rows(summaries[renderer], baseline_summaries, relative_only=True),
                )
            )

        print()


def print_relative_overview(summaries: dict[str, dict[str, SummaryStats]]) -> None:
    print_section_title("Total Relative Overview")
    print(f"Baseline renderer: {BASELINE_RENDERER} = 100%")

    baseline_summaries = summaries.get(BASELINE_RENDERER)
    if baseline_summaries is None:
        print("No linear_sync baseline data found.")
        return

    metric_names = sorted(
        {
            metric_name
            for renderer_metrics in summaries.values()
            for metric_name in renderer_metrics
        },
        key=metric_sort_key,
    )
    renderers = sorted(summaries, key=renderer_sort_key)

    rows: list[list[str]] = []
    for metric_name in metric_names:
        row = [metric_name]
        for renderer in renderers:
            summary = summaries[renderer].get(metric_name)
            baseline_summary = baseline_summaries.get(metric_name)
            if summary is None or baseline_summary is None:
                row.append("n/a")
                continue
            row.append(format_ratio(summary.mean, baseline_summary.mean))
        rows.append(row)

    print(render_table(["metric", *renderers], rows))


def main() -> int:
    args = parse_args()
    log_path = Path(args.logfile)

    records = parse_render_records(log_path)
    if args.size is not None:
        records = [record for record in records if record.command_size == args.size]

    if not records:
        if args.size is None:
            raise SystemExit(f"no render statistics were found in {log_path}")
        raise SystemExit(
            f"no render statistics were found in {log_path} for command size {args.size} bytes"
        )

    grouped = build_grouped_values(records)
    summaries = summarize_renderer_metrics(grouped)
    print_renderer_report(summaries)
    print_relative_overview(summaries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())