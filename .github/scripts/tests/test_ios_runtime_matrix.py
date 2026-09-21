import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "runtime_matrix", Path(__file__).resolve().parents[1] / "ios-runtime-matrix.py"
)
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


def runtime(version, *, available=True, platform="iOS", identifier=None):
    return {
        "version": version,
        "identifier": identifier or f"com.apple.CoreSimulator.SimRuntime.{platform}-{version.replace('.', '-')}",
        "isAvailable": available,
    }


class RuntimeMatrixTests(unittest.TestCase):
    def test_every_supported_minor_and_patch_version_is_selected_in_version_order(self):
        installed = [runtime(version) for version in (
            "27.2", "18.6", "26.4.1", "18.0", "26.2", "27.0", "26.0", "27.10",
            "26.0.1", "26.1", "26.0.2", "26.1.1",
        )]
        jobs = matrix.test_matrix(matrix.supported_runtimes(installed))["include"]
        self.assertEqual(
            [job["version"] for job in jobs],
            ["18.0", "18.6", "26.1", "26.1.1", "26.2", "26.4.1", "27.0", "27.2", "27.10"],
        )

    def test_unavailable_runtimes_other_platforms_and_other_majors_are_excluded(self):
        installed = [
            runtime("17.5"), runtime("18.0"), runtime("27.2", available=False),
            runtime("26.0", platform="tvOS"), runtime("28.0"),
        ]
        self.assertEqual(matrix.supported_runtimes(installed), [installed[1]])

    def test_duplicate_builds_produce_one_job_per_runtime_identifier(self):
        installed = [dict(runtime("27.0"), buildversion=build) for build in ("beta", "release")]
        jobs = matrix.test_matrix(matrix.supported_runtimes(installed))["include"]
        self.assertEqual(jobs, [{"runtime": installed[0]["identifier"], "version": "27.0"}])

    def test_runtime_identifier_is_preserved_when_version_contains_a_patch(self):
        installed = runtime("18.3.1", identifier="com.apple.CoreSimulator.SimRuntime.iOS-18-3")
        jobs = matrix.test_matrix(matrix.supported_runtimes([installed]))["include"]
        self.assertEqual(jobs, [{"runtime": installed["identifier"], "version": "18.3.1"}])

    def test_no_supported_runtime_fails_instead_of_skipping_all_tests(self):
        with self.assertRaisesRegex(ValueError, "No available iOS"):
            matrix.test_matrix([])

    def test_discovery_exports_the_dynamic_matrix(self):
        installed = [runtime("18.6"), runtime("26.5"), runtime("27.2")]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}), \
                    patch("sys.argv", ["ios-runtime-matrix.py", "discover"]), \
                    patch.object(matrix, "simctl", return_value=json.dumps({"runtimes": installed})):
                matrix.main()
            key, value = output.read_text().strip().split("=", 1)
        self.assertEqual(key, "matrix")
        self.assertEqual(json.loads(value), matrix.test_matrix(installed))

    def test_resolution_creates_a_phone_for_the_exact_runtime(self):
        installed = runtime("18.3.1", identifier="com.apple.CoreSimulator.SimRuntime.iOS-18-3")
        installed["supportedDeviceTypes"] = [
            {"identifier": "tablet", "productFamily": "iPad"},
            {"identifier": "phone", "productFamily": "iPhone"},
        ]
        with tempfile.TemporaryDirectory() as directory:
            environment = Path(directory) / "environment"
            with patch.dict(os.environ, {"GITHUB_ENV": str(environment)}), \
                    patch.object(matrix, "simctl", side_effect=[
                        json.dumps({"runtimes": [installed]}), "fresh-udid\n"
                    ]) as simctl:
                matrix.resolve_device(installed["identifier"])
            values = dict(line.split("=", 1) for line in environment.read_text().splitlines())
        self.assertEqual(simctl.call_args_list[-1].args,
                         ("create", "TabBarMenu CI", "phone", installed["identifier"]))
        self.assertEqual(values, {
            "DESTINATION": "platform=iOS Simulator,id=fresh-udid",
            "RESOLVED_IOS_VERSION": "18.3.1",
            "SIMULATOR_UDID": "fresh-udid",
        })

    def test_resolution_does_not_substitute_a_different_runtime(self):
        with patch.object(matrix, "simctl", return_value=json.dumps({
            "runtimes": [runtime("26.5"), runtime("27.2", available=False)]
        })) as simctl:
            with self.assertRaisesRegex(ValueError, "Requested runtime is unavailable"):
                matrix.resolve_device("com.apple.CoreSimulator.SimRuntime.iOS-27-2")
        simctl.assert_called_once_with("list", "runtimes", "--json")


if __name__ == "__main__":
    unittest.main()
