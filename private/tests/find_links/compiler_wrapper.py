"""A small wrapper to a `py_reqs_compiler` that configures a required wheeldir for the find_links tests."""

import os
import subprocess
import sys


def main() -> None:
    """The main entrypoint."""

    workspace_dir = os.environ["BUILD_WORKSPACE_DIRECTORY"]

    environ = dict(os.environ)
    for to_delete in (
        "PYTHONPATH",
        "PYTHONPATHSAFE",
        "BUILD_WORKSPACE_DIRECTORY",
        "BUILD_WORKING_DIRECTORY",
        "BAZELISK_SKIP_WRAPPER",
    ):
        if to_delete in environ:
            del environ[to_delete]

    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "wheel",
            "--wheel-dir",
            workspace_dir / "private/tests/find_links/wheeldir",
            "-r",
            workspace_dir / "private/tests/find_links/requirements.in",
        ],
        cwd=workspace_dir,
        check=True,
        env=environ,
    )

    subprocess.run(
        [
            "bazel",
            "run",
            "//private/tests/find_links:requirements.update",
        ]
        + sys.argv[1:],
        cwd=workspace_dir,
        check=True,
        env=environ,
    )


if __name__ == "__main__":
    main()
