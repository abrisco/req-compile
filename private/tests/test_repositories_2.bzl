"""req-compile Bazel integration test transitive dependencies"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@req_compile_test_annotations//:defs.bzl", annotations_repositories = "repositories")
load("@req_compile_test_cross_platform//:defs.bzl", cross_platform_repositories = "repositories")
load("@req_compile_test_platlib//:defs.bzl", platlib_repositories = "repositories")
load("@req_compile_test_sdist//:defs.bzl", sdist_repositories = "repositories")
load("@req_compile_test_simple//:defs.bzl", simple_repositories = "repositories")
load("@req_compile_test_transitive_ins//:defs.bzl", transitive_ins_repositories = "repositories")
load("//:defs.bzl", "py_requirements_repository")
load("//private/tests/find_links:find_links_test_repo.bzl", "find_links_test_repository")
load(
    "//private/tests/pip_parse_compat:pip_parse_compat_test_deps_install.bzl",
    "pip_parse_compat_test_deps_install",
)

def test_dependencies_2():
    """req-compile Bazel integration test transitive dependencies"""

    annotations_repositories()
    cross_platform_repositories()
    pip_parse_compat_test_deps_install()
    platlib_repositories()
    sdist_repositories()
    simple_repositories()
    transitive_ins_repositories()

    maybe(
        find_links_test_repository,
        name = "req_compile_find_links_test",
        pyspark_wheel_data = Label("@req_compile_test_sdist__pyspark//:whl.json"),
        build_file = Label("//private/tests/find_links:BUILD.find_links.bazel"),
        # Needs to match `--find-links` in `//private/tests/find_links:requirements.in`
        wheeldir = "wheeldir",
        requirements_in = Label("//private/tests/find_links:requirements.in"),
        requirements_txt = Label("//private/tests/find_links:requirements.txt"),
    )

    maybe(
        py_requirements_repository,
        name = "req_compile_test_find_links",
        requirements_lock = Label("@req_compile_find_links_test//:requirements.txt"),
    )
