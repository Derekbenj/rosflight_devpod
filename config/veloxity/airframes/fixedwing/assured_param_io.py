#!/usr/bin/env python3
"""Assurance wrappers for ROSflight parameter persistence and snapshots."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
import time
from pathlib import Path

import rclpy
import yaml
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
from rosflight_msgs.srv import ParamGet
from std_msgs.msg import Bool
from std_srvs.srv import Trigger

from verified_param_loader import (
    call_service,
    format_value,
    load_parameters,
    Parameter,
    read_parameter,
    values_match,
)


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0.0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Assurance wrappers for ROSflight parameter operations."
    )
    subparsers = parser.add_subparsers(dest="operation", required=True)

    write_parser = subparsers.add_parser(
        "write", help="persist parameters and wait for the firmware acknowledgment"
    )
    write_parser.add_argument(
        "--ack-timeout",
        type=positive_float,
        default=5.0,
        help="seconds to wait for the firmware write acknowledgment (default: 5)",
    )
    write_parser.add_argument(
        "--service-timeout",
        type=positive_float,
        default=5.0,
        help="seconds to wait for ROS services and calls (default: 5)",
    )

    save_parser = subparsers.add_parser(
        "save", help="independently read, write, and verify a firmware snapshot"
    )
    save_parser.add_argument("filename", type=Path, help="final snapshot filename")
    save_parser.add_argument(
        "--definitions",
        type=Path,
        required=True,
        help="authoritative Veloxity params.rs or ROSflight C param.cpp",
    )
    save_parser.add_argument(
        "--backend",
        choices=("veloxity", "c"),
        required=True,
        help="syntax used by the parameter-definition source",
    )
    save_parser.add_argument(
        "--sync-timeout",
        type=positive_float,
        default=15.0,
        help="seconds to wait for the complete firmware parameter table (default: 15)",
    )
    save_parser.add_argument(
        "--service-timeout",
        type=positive_float,
        default=5.0,
        help="seconds to wait for ROS services and calls (default: 5)",
    )

    return parser.parse_args()


def wait_for_service(client, name: str, timeout: float) -> bool:
    if client.wait_for_service(timeout_sec=timeout):
        return True
    print(f"FAILED: {name} was unavailable after {timeout:g}s", file=sys.stderr)
    return False


def run_write(args: argparse.Namespace) -> int:
    rclpy.init()
    node = rclpy.create_node("assured_firmware_param_writer")
    write_client = node.create_client(Trigger, "/param_write")

    state = {"count": 0, "unsaved": None}

    def on_unsaved_params(message: Bool) -> None:
        state["count"] += 1
        state["unsaved"] = bool(message.data)

    qos = QoSProfile(depth=1)
    qos.durability = DurabilityPolicy.TRANSIENT_LOCAL
    qos.reliability = ReliabilityPolicy.RELIABLE
    subscription = node.create_subscription(
        Bool, "/status/unsaved_params", on_unsaved_params, qos
    )

    try:
        if not wait_for_service(write_client, "/param_write", args.service_timeout):
            return 2

        # Receive the transient-local baseline first. A later false publication
        # is then unambiguously the firmware's successful write acknowledgment.
        baseline_deadline = time.monotonic() + args.service_timeout
        while state["count"] == 0 and time.monotonic() < baseline_deadline:
            rclpy.spin_once(node, timeout_sec=0.1)
        if state["count"] == 0:
            print(
                "FAILED: no baseline received from /status/unsaved_params",
                file=sys.stderr,
            )
            return 3

        baseline_count = state["count"]
        response, error = call_service(
            node, write_client, Trigger.Request(), args.service_timeout
        )
        if error is not None:
            print(f"FAILED: /param_write: {error}", file=sys.stderr)
            return 4
        if not response.success:
            detail = response.message or "request was rejected"
            print(f"FAILED: /param_write: {detail}", file=sys.stderr)
            return 4

        deadline = time.monotonic() + args.ack_timeout
        while time.monotonic() < deadline:
            rclpy.spin_once(
                node, timeout_sec=min(0.1, max(0.0, deadline - time.monotonic()))
            )
            if state["count"] > baseline_count and state["unsaved"] is False:
                print("PASS: firmware acknowledged persistent parameter storage.")
                return 0

        print(
            "FAILED: /param_write was accepted, but no successful firmware "
            f"acknowledgment arrived within {args.ack_timeout:g}s",
            file=sys.stderr,
        )
        return 5
    finally:
        # Keep a reference through the final spin/destruction on older rclpy.
        _ = subscription
        node.destroy_node()
        rclpy.shutdown()


def wait_for_complete_table(
    node: Node, client, sync_timeout: float, service_timeout: float
) -> str | None:
    deadline = time.monotonic() + sync_timeout
    last_detail = "not all parameters received from firmware"
    while True:
        response, error = call_service(
            node, client, Trigger.Request(), service_timeout
        )
        if error is not None:
            last_detail = error
        elif response.success:
            return None
        else:
            last_detail = response.message or last_detail

        if time.monotonic() >= deadline:
            return last_detail
        time.sleep(0.25)


def load_definitions(filename: Path, backend: str) -> list[tuple[str, int]]:
    try:
        source = filename.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"cannot read parameter definitions {filename}: {exc}") from exc

    if backend == "veloxity":
        pattern = re.compile(
            r'^\s*[A-Z][A-Z0-9_]*,\s*"([A-Z0-9_]+)",\s*'
            r'(Float|Int|Uint|Bool)\(',
            re.MULTILINE,
        )
        type_map = {"Float": 9, "Int": 6, "Uint": 5, "Bool": 1}
        definitions = [(name, type_map[kind]) for name, kind in pattern.findall(source)]
    else:
        pattern = re.compile(
            r'init_param_(int|float)\([^,]+,\s*"([A-Z0-9_]+)"',
            re.MULTILINE,
        )
        type_map = {"int": 6, "float": 9}
        definitions = [(name, type_map[kind]) for kind, name in pattern.findall(source)]

    if not definitions:
        raise ValueError(
            f"{filename}: found no {backend} firmware parameter definitions"
        )
    names = [name for name, _ in definitions]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise ValueError(f"{filename}: duplicate parameter definitions: {duplicates}")
    return definitions


def read_defined_values(
    node: Node, get_client, definitions: list[tuple[str, int]], service_timeout: float
) -> tuple[list[Parameter], list[str]]:
    parameters: list[Parameter] = []
    failures: list[str] = []
    for name, mav_type in definitions:
        result = read_parameter(node, get_client, name, service_timeout)
        if result.value is None:
            failures.append(f"{name}: {result.error or 'value unavailable'}")
        else:
            parameters.append(Parameter(name, mav_type, result.value))
    return parameters, failures


def write_snapshot(filename: Path, parameters: list[Parameter]) -> None:
    document = [
        {"name": parameter.name, "type": parameter.mav_type, "value": parameter.value}
        for parameter in parameters
    ]
    with filename.open("w", encoding="utf-8") as stream:
        yaml.safe_dump(document, stream, sort_keys=False)
        stream.flush()
        os.fsync(stream.fileno())


def verify_snapshot(
    node: Node, get_client, filename: Path, service_timeout: float,
    expected_names: list[str],
) -> tuple[list[Parameter], list[str]]:
    try:
        parameters = load_parameters(filename)
    except ValueError as exc:
        return [], [str(exc)]

    mismatches: list[str] = []
    actual_names = [parameter.name for parameter in parameters]
    if actual_names != expected_names:
        missing = sorted(set(expected_names) - set(actual_names))
        extra = sorted(set(actual_names) - set(expected_names))
        mismatches.append(
            "snapshot parameter sequence differs from firmware definitions"
            + (f"; missing={missing}" if missing else "")
            + (f"; extra={extra}" if extra else "")
        )
    for parameter in parameters:
        result = read_parameter(node, get_client, parameter.name, service_timeout)
        if result.value is None or not values_match(parameter, result.value):
            detail = result.error or f"cache has {format_value(result.value)}"
            mismatches.append(
                f"{parameter.name}: file has {format_value(parameter.value)}, {detail}"
            )
    return parameters, mismatches


def run_save(args: argparse.Namespace) -> int:
    destination = args.filename.expanduser().resolve()
    definitions_filename = args.definitions.expanduser().resolve()
    try:
        definitions = load_definitions(definitions_filename, args.backend)
    except ValueError as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 2

    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
    )
    os.close(fd)
    temporary = Path(temporary_name)

    rclpy.init()
    node = rclpy.create_node("assured_firmware_param_snapshot")
    complete_client = node.create_client(Trigger, "/all_params_received")
    get_client = node.create_client(ParamGet, "/param_get")

    try:
        for name, client in (
            ("/all_params_received", complete_client),
            ("/param_get", get_client),
        ):
            if not wait_for_service(client, name, args.service_timeout):
                return 2

        sync_error = wait_for_complete_table(
            node,
            complete_client,
            args.sync_timeout,
            args.service_timeout,
        )
        if sync_error is not None:
            print(
                "FAILED: refusing to save an incomplete parameter snapshot: "
                f"{sync_error}",
                file=sys.stderr,
            )
            return 3

        parameters, failures = read_defined_values(
            node, get_client, definitions, args.service_timeout
        )
        if failures:
            print(
                f"FAILED: could not read {len(failures)} of {len(definitions)} "
                "source-defined parameters:",
                file=sys.stderr,
            )
            for failure in failures:
                print(f"  - {failure}", file=sys.stderr)
            return 4

        write_snapshot(temporary, parameters)
        parsed_parameters, mismatches = verify_snapshot(
            node,
            get_client,
            temporary,
            args.service_timeout,
            [name for name, _ in definitions],
        )
        if mismatches:
            print(
                f"FAILED: snapshot verification found {len(mismatches)} issue(s):",
                file=sys.stderr,
            )
            for mismatch in mismatches:
                print(f"  - {mismatch}", file=sys.stderr)
            return 5

        os.replace(temporary, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        print(
            f"PASS: independently saved and verified {len(parsed_parameters)} "
            f"parameters in {destination}"
        )
        return 0
    finally:
        if temporary.exists():
            temporary.unlink()
        node.destroy_node()
        rclpy.shutdown()


def main() -> int:
    args = parse_args()
    if args.operation == "write":
        return run_write(args)
    if args.operation == "save":
        return run_save(args)
    raise AssertionError(f"unsupported operation: {args.operation}")


if __name__ == "__main__":
    raise SystemExit(main())
