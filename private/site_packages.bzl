"""A rule laying out Python sources as an installed package."""

load("@rules_python//python:defs.bzl", "py_library")

def _normalize_distribution(name):
    """Normalize a distribution name for a `.dist-info` directory, see PEP 427."""
    return "".join([
        char if char.isalnum() else "_"
        for char in name.elems()
    ])

def _installed_path(ctx, file):
    """The path of a file relative to the package, with `strip_prefix` removed."""
    if file.owner.package != ctx.label.package:
        fail("`{}` is not in the package of `{}`. `py_site_packages` can only lay out files of its own package.".format(
            file.owner,
            ctx.label,
        ))
    path = file.owner.name
    prefix = ctx.attr.strip_prefix.strip("/")
    if prefix:
        if not path.startswith(prefix + "/"):
            fail("`{}` does not start with the `strip_prefix` `{}` of `{}`.".format(
                path,
                prefix,
                ctx.label,
            ))
        path = path[len(prefix) + 1:]
    return path

def _py_site_packages_files_impl(ctx):
    outputs = []
    top_level = {}
    for src in ctx.files.srcs + ctx.files.data:
        path = _installed_path(ctx, src)
        output = ctx.actions.declare_file("site-packages/" + path)
        ctx.actions.symlink(output = output, target_file = src)
        outputs.append(output)

        first, _, _ = path.partition("/")
        if "/" not in path:
            first, _, _ = path.rpartition(".")
        top_level[first] = True

    dist_info = "site-packages/{}-{}.dist-info".format(
        _normalize_distribution(ctx.attr.distribution),
        ctx.attr.version,
    )

    metadata = ctx.actions.declare_file(dist_info + "/METADATA")
    if ctx.file.metadata:
        ctx.actions.symlink(output = metadata, target_file = ctx.file.metadata)
    else:
        ctx.actions.write(metadata, "Metadata-Version: 2.1\nName: {}\nVersion: {}\n".format(
            ctx.attr.distribution,
            ctx.attr.version,
        ))
    outputs.append(metadata)

    installer = ctx.actions.declare_file(dist_info + "/INSTALLER")
    ctx.actions.write(installer, "rules_req_compile\n")
    outputs.append(installer)

    top_level_txt = ctx.actions.declare_file(dist_info + "/top_level.txt")
    ctx.actions.write(top_level_txt, "\n".join(sorted(top_level)) + "\n")
    outputs.append(top_level_txt)

    if ctx.attr.entry_points:
        entry_points = ctx.actions.declare_file(dist_info + "/entry_points.txt")
        ctx.actions.write(entry_points, "[console_scripts]\n" + "".join([
            "{} = {}\n".format(script, target)
            for script, target in sorted(ctx.attr.entry_points.items())
        ]))
        outputs.append(entry_points)

    return [DefaultInfo(files = depset(outputs))]

_py_site_packages_files = rule(
    doc = "Lay out files as an installed Python package under `site-packages`.",
    implementation = _py_site_packages_files_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Files to install alongside the sources.",
            allow_files = True,
        ),
        "distribution": attr.string(
            doc = "The name of the distribution.",
            mandatory = True,
        ),
        "entry_points": attr.string_dict(
            doc = "Console scripts as a mapping of script name to `module:attribute`.",
        ),
        "metadata": attr.label(
            doc = "The core metadata of the distribution, e.g. the `PKG-INFO` of a source distribution.",
            allow_single_file = True,
        ),
        "srcs": attr.label_list(
            doc = "The Python sources to install.",
            allow_files = [".py"],
        ),
        "strip_prefix": attr.string(
            doc = "A directory prefix to remove from the paths of `srcs` and `data`.",
        ),
        "version": attr.string(
            doc = "The version of the distribution.",
            mandatory = True,
        ),
    },
)

def py_site_packages(
        name,
        distribution,
        version,
        srcs = [],
        data = [],
        strip_prefix = "",
        metadata = None,
        entry_points = {},
        deps = [],
        **kwargs):
    """Install Python sources as a package in a `site-packages` directory.

    This lays out `srcs` and `data` under `site-packages` as `pip` would install them, writes the
    `.dist-info` directory holding the metadata of the distribution so `importlib.metadata` can find
    it, and defines a `py_library` importing from that directory. It is meant for `BUILD` files given
    to the `build_file` annotation of a package, which replace building a source distribution with an
    interpreter by a Bazel build of its sources.

    ```python
    load("@rules_req_compile//:defs.bzl", "py_site_packages")
    load(":package.bzl", "ARCHIVE", "ENTRY_POINTS", "PACKAGE", "SOURCE_DIR", "VERSION")

    py_site_packages(
        name = "library",
        srcs = glob([SOURCE_DIR + "/src/**/*.py"]),
        data = glob([SOURCE_DIR + "/src/**/*.txt"]),
        distribution = PACKAGE,
        entry_points = ENTRY_POINTS,
        metadata = SOURCE_DIR + "/PKG-INFO",
        strip_prefix = SOURCE_DIR + "/src",
        version = VERSION,
    )
    ```

    No `RECORD` file is written, so tools that list installed files, such as `pip`, do not see
    the package. Anything a `setup.py` would generate has to be produced by other targets and
    passed in `srcs` or `data`.

    Args:
        name (str): The name of the `py_library`.
        distribution (str): The name of the distribution.
        version (str): The version of the distribution.
        srcs (list): The Python sources to install, in the same package as this target.
        data (list): Files to install alongside the sources.
        strip_prefix (str): A directory prefix to remove from the paths of `srcs` and `data`, e.g.
            the `src` directory of a source distribution.
        metadata (Label): The core metadata of the distribution, e.g. the `PKG-INFO` of a source
            distribution. A minimal `METADATA` is written when omitted.
        entry_points (dict): Console scripts as a mapping of script name to `module:attribute`.
        deps (list): Dependencies of the `py_library`. Hubs add the dependencies they resolved
            themselves, so this is only needed for dependencies outside the hub.
        **kwargs (dict): Additional keyword arguments for the `py_library`.
    """
    _py_site_packages_files(
        name = name + ".site_packages",
        data = data,
        distribution = distribution,
        entry_points = entry_points,
        metadata = metadata,
        srcs = srcs,
        strip_prefix = strip_prefix,
        version = version,
        visibility = ["//visibility:private"],
    )

    py_library(
        name = name,
        data = [":" + name + ".site_packages"],
        imports = ["site-packages"],
        deps = deps,
        **kwargs
    )
