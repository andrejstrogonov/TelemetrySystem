#!/usr/bin/env python3
"""Fit the fixed-point Ethernet packet score from a labeled CSV (stdlib only)."""

import argparse
import csv
import sys


FEATURES = (
    "multicast",
    "arp",
    "ipv4",
    "ipv6",
    "vlan",
    "tcp",
    "udp",
    "port23",
    "unknown",
)
TARGET = "unwanted"


def solve_linear_system(matrix, vector):
    """Gauss-Jordan elimination with partial pivoting."""
    size = len(vector)
    augmented = [list(matrix[row]) + [vector[row]] for row in range(size)]
    for column in range(size):
        pivot = max(range(column, size), key=lambda row: abs(augmented[row][column]))
        if abs(augmented[pivot][column]) < 1e-12:
            raise ValueError("training features are rank deficient; add varied labeled packets")
        augmented[column], augmented[pivot] = augmented[pivot], augmented[column]
        divisor = augmented[column][column]
        augmented[column] = [value / divisor for value in augmented[column]]
        for row in range(size):
            if row == column:
                continue
            factor = augmented[row][column]
            augmented[row] = [
                augmented[row][index] - factor * augmented[column][index]
                for index in range(size + 1)
            ]
    return [augmented[row][-1] for row in range(size)]


def read_training_data(path):
    rows = []
    labels = []
    with open(path, newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        required = set(FEATURES) | {TARGET}
        missing = required - set(reader.fieldnames or ())
        if missing:
            raise ValueError("missing CSV columns: " + ", ".join(sorted(missing)))
        for line_number, row in enumerate(reader, start=2):
            try:
                values = [int(row[name]) for name in FEATURES]
                label = int(row[TARGET])
            except (TypeError, ValueError) as error:
                raise ValueError(f"line {line_number}: features and unwanted must be 0 or 1") from error
            if any(value not in (0, 1) for value in values) or label not in (0, 1):
                raise ValueError(f"line {line_number}: features and unwanted must be 0 or 1")
            rows.append([1.0] + [float(value) for value in values])
            labels.append(float(label))
    if len(rows) < len(FEATURES) + 1:
        raise ValueError(f"need at least {len(FEATURES) + 1} rows for the bias and features")
    return rows, labels


def fit_ols(rows, labels):
    width = len(rows[0])
    normal = [[0.0] * width for _ in range(width)]
    target = [0.0] * width
    for row, label in zip(rows, labels):
        for i in range(width):
            target[i] += row[i] * label
            for j in range(width):
                normal[i][j] += row[i] * row[j]
    return solve_linear_system(normal, target)


def verilog_integer(value):
    return f"-24'sd{abs(value)}" if value < 0 else f"24'sd{value}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", help="labeled packet feature CSV")
    parser.add_argument("--scale", type=int, default=256, help="fixed-point scale (default: 256)")
    args = parser.parse_args()
    if args.scale <= 0:
        parser.error("--scale must be positive")

    try:
        rows, labels = read_training_data(args.csv)
        floating_weights = fit_ols(rows, labels)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    quantized = [round(weight * args.scale) for weight in floating_weights]
    limit = (1 << 23) - 1
    if any(weight < -limit - 1 or weight > limit for weight in quantized):
        print("error: quantized coefficient does not fit signed 24-bit RTL parameter", file=sys.stderr)
        return 2

    names = ("BIAS",) + tuple(name.upper() for name in FEATURES)
    print("// Copy these values to the MODEL_* parameters in gowin_ethernet_filter_top.")
    for name, value in zip(names, quantized):
        print(f".MODEL_W_{name}({verilog_integer(value)}),")
    print(f".MODEL_THRESHOLD({verilog_integer(args.scale // 2)})")
    print("// Unwanted when score >= threshold. Review the quantized model before programming.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
