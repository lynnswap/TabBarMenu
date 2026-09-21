#!/usr/bin/env python3
"""Discover supported installed iOS runtimes and create test Simulators."""

import argparse
import json
import os
import subprocess
from pathlib import Path


def version_components(version):
    return tuple((list(map(int, version.split("."))) + [0, 0])[:3])


def supported_runtimes(runtimes):
    # Multiple installed builds can share one runtime identifier. simctl selects
    # the installed build for that identifier when creating a destination.
    selected = {}
    for runtime in runtimes:
        if not runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        if not runtime.get("isAvailable", False):
            continue
        version = version_components(runtime["version"])
        if version[0] not in {18, 26, 27} or (26, 0, 0) <= version < (26, 1, 0):
            continue
        selected[runtime["identifier"]] = runtime
    return sorted(selected.values(), key=lambda runtime: version_components(runtime["version"]))


def test_matrix(runtimes):
    if not runtimes:
        raise ValueError("No available iOS 18.x, 26.1+, or 27.x runtime is installed.")
    return {"include": [
        {"runtime": runtime["identifier"], "version": runtime["version"]}
        for runtime in runtimes
    ]}


def simctl(*arguments):
    return subprocess.check_output(["xcrun", "simctl", *arguments], text=True)


def append_environment(values):
    with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
        for name, value in values.items():
            stream.write(f"{name}={value}\n")


def resolve_device(runtime_id):
    runtimes = supported_runtimes(json.loads(simctl("list", "runtimes", "--json"))["runtimes"])
    runtime = next((runtime for runtime in runtimes if runtime["identifier"] == runtime_id), None)
    if runtime is None:
        raise ValueError(f"Requested runtime is unavailable: {runtime_id}")
    device_type = next(device_type for device_type in runtime["supportedDeviceTypes"]
                       if device_type["productFamily"] == "iPhone")
    udid = simctl("create", "TabBarMenu CI", device_type["identifier"], runtime_id).strip()
    append_environment({
        "DESTINATION": f"platform=iOS Simulator,id={udid}",
        "RESOLVED_IOS_VERSION": runtime["version"],
        "SIMULATOR_UDID": udid,
    })
    print(f"iOS {runtime['version']}: {udid}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("discover")
    resolve = commands.add_parser("resolve")
    resolve.add_argument("--runtime", required=True)
    args = parser.parse_args()

    if args.command == "resolve":
        resolve_device(args.runtime)
        return
    runtimes = supported_runtimes(json.loads(simctl("list", "runtimes", "--json"))["runtimes"])
    matrix = test_matrix(runtimes)
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"matrix={json.dumps(matrix)}\n")
    for runtime in runtimes:
        print(f"iOS {runtime['version']}: {runtime['identifier']}")


if __name__ == "__main__":
    main()
