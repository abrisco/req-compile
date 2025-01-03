"""Integration tests."""
import os
import subprocess
import sys

from req_compile.config import read_pip_default_index

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), os.path.pardir))


def test_source_candidates():
    """Verify the current directory shows a candidate."""
    result = subprocess.run(
        [sys.executable, "-m", "req_compile.candidates", "--pre"],
        encoding="utf-8",
        capture_output=True,
        cwd=ROOT_DIR,
        check=True,
    )
    assert "req-compile" in result.stdout
    assert result.stdout.count("\n") == 1
    assert "Found 1 compatible" in result.stderr


def test_no_candidates(tmp_path):
    """Verify finding no candidates works correctly."""
    env_copy = os.environ.copy()
    env_copy["PYTHONPATH"] = ROOT_DIR

    result = subprocess.run(
        [sys.executable, "-m", "req_compile.candidates", "--pre"],
        encoding="utf-8",
        capture_output=True,
        env=env_copy,
        cwd=tmp_path,
        check=True,
    )
    assert result.stdout == ""
    assert "0" in result.stderr, result.stderr


def test_compile_req_compile(tmp_path):
    """Test compiling this project from source."""
    try:
        result = subprocess.run(
            [
                sys.executable,
                "-W",
                "ignore",
                "-m",
                "req_compile",
                "-i",
                read_pip_default_index() or "https://pypi.org/simple",
                ".",
                "--wheel-dir",
                str(tmp_path),
            ],
            check=True,
            encoding="utf-8",
            capture_output=True,
            cwd=ROOT_DIR,
        )
    except subprocess.CalledProcessError as ex:
        print(ex.stdout, file=sys.stderr)
        print(ex.stderr, file=sys.stderr)
        raise

    assert "req-compile" in result.stdout
    assert "toml" in result.stdout
    assert result.stderr == "", result.stderr

    # Ensure that setup requires are included.
    all_items = {path.name.split("-", 1)[0] for path in tmp_path.iterdir()}
    assert "setuptools" in all_items
