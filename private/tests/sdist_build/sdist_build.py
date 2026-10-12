"""Check a source distribution built by Bazel through a `build_file` annotation."""

import importlib.metadata
import os
import subprocess
import unittest
from pathlib import Path

from python.runfiles import Runfiles  # pylint: disable=import-error
from sdist_build_example import __version__  # pylint: disable=import-error


class SdistBuildTest(unittest.TestCase):
    def test_import(self) -> None:
        self.assertEqual(__version__, "1.0.0")

    def test_metadata(self) -> None:
        distribution = importlib.metadata.distribution("sdist-build-example")
        self.assertEqual(distribution.version, "1.0.0")
        self.assertEqual(
            distribution.read_text("INSTALLER").strip(), "rules_req_compile"
        )
        self.assertEqual(
            distribution.read_text("top_level.txt").strip(), "sdist_build_example"
        )
        scripts = {
            entry.name: entry.value
            for entry in distribution.entry_points
            if entry.group == "console_scripts"
        }
        self.assertEqual(
            scripts, {"sdist-build-example": "sdist_build_example.cli:main"}
        )

    def test_entry_point(self) -> None:
        runfiles = Runfiles.Create()
        assert runfiles, "Failed to locate runfiles"
        binary = runfiles.Rlocation(os.environ["EXAMPLE_BIN"])
        assert binary and Path(binary).exists(), binary
        output = subprocess.run(
            [binary],
            check=True,
            capture_output=True,
            text=True,
            env=dict(os.environ, **runfiles.EnvVars()),
        ).stdout
        self.assertEqual(output.strip(), "built by bazel")


if __name__ == "__main__":
    unittest.main()
