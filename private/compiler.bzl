"""Rules for compiling requirements files"""

PyReqsCompilerInfo = provider(
    doc = "Information about a python requirements provider",
    fields = {
        "args": "List[str]: A list of arguments core to the compiler.",
        "requirements_in": "Target: The `requirements_in` target which provides requirement files.",
        "solution": "Target: The solution file which represents the compiled result from `requirements_in`.",
    },
)

def _rlocationpath(file, workspace_name):
    """A convenience method for producing the `rlocationpath` of a file.

    Args:
        file (File): The file object to generate the path for.
        workspace_name (str): The current workspace name.

    Returns:
        str: The `rlocationpath` value.
    """
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _symlink_py_executable(ctx, target):
    """Create an executable symlink to a `py_bianry` entrypoint.

    This function exists because executable rules __must__ produce the executable it represents.

    Args:
        ctx (ctx): The rule's context object
        target (Target): The `py_binary` target to create symlinks for.

    Returns:
        Tuple[File, Runfiles]: The executable output and associated runfiles.
    """
    executable = target[DefaultInfo].files_to_run.executable
    is_windows = executable.basename.endswith(".exe")
    link = ctx.actions.declare_file("{}.{}".format(ctx.label.name, executable.basename))

    ctx.actions.symlink(
        output = link,
        target_file = executable,
        is_executable = True,
    )

    runfiles = ctx.runfiles()
    runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

    # Windows will require the zipapp provided by py_binary targets
    if is_windows and hasattr(target[OutputGroupInfo], "python_zip_file"):
        _, _, zipapp_name = link.path.rpartition("/")
        zipapp = ctx.actions.declare_file(zipapp_name.replace(".exe", ".zip"), sibling = link)

        # This output group is expected to only contain 1 file
        python_zip_file = target[OutputGroupInfo].python_zip_file.to_list()[0]
        ctx.actions.symlink(
            output = zipapp,
            target_file = python_zip_file,
            is_executable = True,
        )
        runfiles = runfiles.merge(ctx.runfiles(files = [zipapp]))

    return link, runfiles

def _py_reqs_compiler_impl(ctx):
    compiler, runfiles = _symlink_py_executable(ctx, ctx.attr._compiler)

    if ctx.attr.custom_compile_command:
        custom_compile_command = ctx.attr.custom_compile_command
    else:
        custom_compile_command = "bazel run {}".format(ctx.label)

    args = [
        "--requirements_file",
        _rlocationpath(ctx.file.requirements_in, ctx.workspace_name),
        "--solution",
        _rlocationpath(ctx.file.requirements_txt, ctx.workspace_name),
        "--custom_compile_command",
        json.encode(custom_compile_command),
    ]

    if ctx.attr.allow_sdists:
        args.append("--allow_sdists")

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = "\n".join(args + [
            "--output",
            ctx.file.requirements_txt.short_path,
        ]),
    )

    runfiles = runfiles.merge_all([
        ctx.runfiles(files = [
            args_file,
            ctx.file.requirements_in,
            ctx.file.requirements_txt,
        ]),
        ctx.attr.requirements_in[DefaultInfo].default_runfiles,
    ])

    return [
        RunEnvironmentInfo(
            environment = {
                "PY_REQ_COMPILER_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
        DefaultInfo(
            executable = compiler,
            files = depset([compiler]),
            runfiles = runfiles,
        ),
        PyReqsCompilerInfo(
            args = args,
            requirements_in = ctx.attr.requirements_in,
            solution = ctx.attr.requirements_txt,
        ),
    ]

py_reqs_compiler = rule(
    doc = """\
A Bazel rule for compiling python requirements for the current platform.


```python
load("@req_compile//:defs.bzl", "py_reqs_compiler", "py_reqs_solution_test")

filegroup(
    name = "requriements",
    srcs = ["requirements.in"],
    data = [
        # Any transitive files included via `-r` should be added here.
    ],
)

py_reqs_compiler(
    name = "requirements.update",
    requirements_in = ":requirements",
    requirements_txt = "requirements.txt",
)

```

Updating requirements can be performed by running the new target.

```bash
bazel run //:requirements.update
```

By default the rule will try to recycle pins already existing in the solution file (`requirements.txt`). To perform
a clean resolution (fetching latest for all requirements) the `--upgrade` flag can be used.

```bash
bazel run //:requirements.update -- --upgrade
```
""",
    implementation = _py_reqs_compiler_impl,
    attrs = {
        "allow_sdists": attr.bool(
            doc = "Whether or not the solution file is allowed to contain sdist packages.",
            default = False,
        ),
        "custom_compile_command": attr.string(
            doc = "The command to display in the header of the generated lock file (`requirements_txt`). Defaults to `bazel run ${label}`.",
        ),
        "requirements_in": attr.label(
            doc = "The input requirements file",
            allow_single_file = True,
            mandatory = True,
        ),
        "requirements_txt": attr.label(
            doc = "The solution file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "_compiler": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//private:compiler"),
        ),
    },
    executable = True,
)

def _py_reqs_solution_test_impl(ctx):
    tester, runfiles = _symlink_py_executable(ctx, ctx.attr._tester)

    compile_info = ctx.attr.compiler[PyReqsCompilerInfo]

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = "\n".join(compile_info.args + [
            "--no_index",
        ]),
    )

    runfiles = runfiles.merge_all([
        ctx.runfiles(
            files = [args_file],
            transitive_files = depset(transitive = [
                compile_info.requirements_in[DefaultInfo].files,
                compile_info.solution[DefaultInfo].files,
            ]),
        ),
        compile_info.requirements_in[DefaultInfo].default_runfiles,
        compile_info.solution[DefaultInfo].default_runfiles,
    ])

    return [
        RunEnvironmentInfo(
            environment = {
                "PY_REQ_COMPILER_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
        DefaultInfo(
            executable = tester,
            files = depset([tester]),
            runfiles = runfiles,
        ),
    ]

py_reqs_solution_test = rule(
    doc = """\
A Bazel test rule for ensuring the solution file for a `py_reqs_compiler` target satisifes the given requirements (`requirements_in`).

```python
load("@req_compile//:defs.bzl", "py_reqs_compiler", "py_reqs_solution_test")

py_reqs_compiler(
    name = "requirements.update",
    requirements_in = "requirements.in",
    requirements_txt = "requirements.txt",
)

py_reqs_compiler(
    name = "requirements_test",
    compiler = ":requirements.update",
)
```
""",
    implementation = _py_reqs_solution_test_impl,
    attrs = {
        "compiler": attr.label(
            doc = "The `py_reqs_compiler` target to test.",
            mandatory = True,
            providers = [PyReqsCompilerInfo],
        ),
        "_tester": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//private:solution_tester"),
        ),
    },
    test = True,
)
