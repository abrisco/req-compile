"""A repository rule for the req-compile find_links integration test."""

def _find_links_test_repository_impl(repository_ctx):
    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

    content = repository_ctx.read(repository_ctx.path(repository_ctx.attr.build_file))
    repository_ctx.file("BUILD.bazel", content)

    wheel = repository_ctx.path(repository_ctx.attr.pyspark_wheel)
    repository_ctx.symlink(
        wheel,
        "{}/{}".format(repository_ctx.attr.wheeldir, wheel.basename),
    )

    reqs_in = repository_ctx.path(repository_ctx.attr.requirements_in)
    repository_ctx.symlink(
        reqs_in,
        reqs_in.basename,
    )

    reqs_txt = repository_ctx.path(repository_ctx.attr.requirements_txt)
    repository_ctx.symlink(
        reqs_txt,
        reqs_txt.basename,
    )

find_links_test_repository = repository_rule(
    doc = "A repository rule for the req-compile find_links integration test.",
    implementation = _find_links_test_repository_impl,
    attrs = {
        "build_file": attr.label(
            doc = "The BUILD file to use for the repo.",
            allow_files = True,
            mandatory = True,
        ),
        "pyspark_wheel": attr.label(
            doc = "The path to a wheel to embed in `wheeldir`",
            allow_files = True,
            mandatory = True,
        ),
        "requirements_in": attr.label(
            doc = "The `requirements.in` file.",
            allow_files = True,
            mandatory = True,
        ),
        "requirements_txt": attr.label(
            doc = "The `requirements.txt` file.",
            allow_files = True,
            mandatory = True,
        ),
        "wheeldir": attr.string(
            doc = "The name of the wheeldir directory.",
            mandatory = True,
        ),
    },
)
