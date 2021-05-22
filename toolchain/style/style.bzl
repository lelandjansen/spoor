# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

load("@rules_cc//cc:action_names.bzl", "CPP_COMPILE_ACTION_NAME")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@bazel_skylib//rules:copy_file.bzl", "copy_file")

def _run_clang_format(
        ctx,
        clang_format_config,
        clang_format_executable,
        input_file):
    inputs = depset(direct = clang_format_config.to_list() + [input_file])

    output_file_name = "{}.formatted.{}".format(
        input_file.basename[:(-1 * (len(input_file.extension) + 1))],
        input_file.extension,
    )
    output_file = ctx.actions.declare_file(output_file_name)

    args = ctx.actions.args()
    args.add(output_file.path)
    args.add(input_file.path)
    args.add("-style=file")
    args.add("-i")

    ctx.actions.run(
        outputs = [output_file],
        inputs = inputs,
        executable = clang_format_executable,
        arguments = [args],
        mnemonic = "ClangFormat",
        progress_message = "Formatting {}".format(input_file.short_path),
        use_default_shell_env = True,
        execution_requirements = {
            "no-sandbox": "True",  # Allow in-place source file modification.
        },
    )

    return output_file

def _run_yapf(
        ctx,
        yapf_config,
        yapf_executable,
        input_file):
    inputs = depset(direct = yapf_config.to_list() + [input_file])

    output_file_name = "{}.formatted.{}".format(
        input_file.basename[:(-1 * (len(input_file.extension) + 1))],
        input_file.extension,
    )
    output_file = ctx.actions.declare_file(output_file_name)

    args = ctx.actions.args()
    args.add(output_file.path)
    args.add(input_file.path)
    args.add("--in-place")

    ctx.actions.run(
        outputs = [output_file],
        inputs = inputs,
        executable = yapf_executable,
        arguments = [args],
        mnemonic = "YAPF",
        progress_message = "Formatting {}".format(input_file.short_path),
        use_default_shell_env = True,
        execution_requirements = {
            "no-sandbox": "True",  # Allow in-place source file modification.
        },
    )

    return output_file

def _run_clang_tidy(
        ctx,
        clang_tidy_config,
        clang_tidy_executable,
        flags,
        compilation_context,
        input_file,
        target_name):
    inputs = depset(
        direct = clang_tidy_config.to_list() + [input_file],
        transitive = [compilation_context.headers],
    )

    output_file_name = "{}.{}.clang_tidy.yml".format(
        input_file.basename.replace(".", "_"),
        target_name,
    )
    output_file = ctx.actions.declare_file(output_file_name)

    source_exclusions = [
        "spoor/runtime/wrappers/objc/SpoorConfig.h",
        "spoor/runtime/wrappers/objc/SpoorConfig.mm",
        "spoor/runtime/wrappers/objc/SpoorConfigTests.mm",
        "spoor/runtime/wrappers/objc/SpoorConfig_private.h",
        "spoor/runtime/wrappers/objc/SpoorDeletedFilesInfo.h",
        "spoor/runtime/wrappers/objc/SpoorDeletedFilesInfo.mm",
        "spoor/runtime/wrappers/objc/SpoorDeletedFilesInfoTests.mm",
        "spoor/runtime/wrappers/objc/SpoorDeletedFilesInfo_private.h",
        "spoor/runtime/wrappers/objc/SpoorRuntime.h",
        "spoor/runtime/wrappers/objc/SpoorRuntime.mm",
        "spoor/runtime/wrappers/objc/SpoorRuntimeStubTests.mm",
        "spoor/runtime/wrappers/objc/SpoorRuntimeTests.mm",
        "spoor/runtime/wrappers/objc/SpoorTypes.h",
        "spoor/runtime/wrappers/objc/SpoorTypesTests.mm",
    ]
    if input_file.path in source_exclusions:
        ctx.actions.run_shell(
            outputs = [output_file],
            mnemonic = "CreateEmptyFile",
            progress_message = "Creating {}".format(input_file.short_path),
            command = "touch {}".format(output_file.path),
        )
        return output_file

    # Exclude files by only linting lines out of its range.
    exclude = [[100000, 100000]]
    filter_exclusions = [
        ".pb.h",
        "spoor/runtime/runtime.h",
    ]
    filter_inclusions = [
        ".cc",
        ".h",
    ]
    line_filter = struct(
        key = [struct(name = e, lines = exclude) for e in filter_exclusions] +
              [struct(name = i) for i in filter_inclusions],
    ).to_json()[len("{\"key\":"):(-1 * len("}"))]

    args = ctx.actions.args()
    args.add(input_file.path)
    args.add("--export-fixes", output_file.path)
    args.add("--line-filter={}".format(line_filter))
    args.add("--")
    args.add_all(flags)
    args.add_all(
        compilation_context.defines.to_list(),
        format_each = "-D%s",
    )
    args.add_all(
        compilation_context.local_defines.to_list(),
        format_each = "-D%s",
    )
    args.add_all(
        compilation_context.framework_includes.to_list(),
        format_each = "-F%s",
    )
    args.add_all(
        compilation_context.includes.to_list(),
        format_each = "-I%s",
    )
    args.add_all(
        compilation_context.system_includes.to_list(),
        before_each = "-isystem",
    )
    args.add_all(
        compilation_context.quote_includes.to_list(),
        before_each = "-iquote",
    )

    ctx.actions.run(
        outputs = [output_file],
        inputs = inputs,
        executable = clang_tidy_executable,
        arguments = [args],
        mnemonic = "ClangTidy",
        progress_message = "Tidying {}".format(input_file.short_path),
        use_default_shell_env = True,
    )

    return output_file

def _clang_format_impl(target, ctx):
    clang_format_config = ctx.attr._clang_format_config.data_runfiles.files
    yapf_config = ctx.attr._yapf_config.data_runfiles.files
    clang_format_executable = ctx.attr._clang_format_executable.files_to_run
    yapf_executable = ctx.attr._yapf_executable.files_to_run

    clang_format_extensions = ["cc", "h", "m", "mm", "proto"]
    yapf_extensions = ["py"]
    clang_format_input_files = []
    yapf_input_files = []
    for input_target in getattr(ctx.rule.attr, "srcs", []):
        for file in input_target.files.to_list():
            if file.is_source:
                if file.extension in clang_format_extensions:
                    clang_format_input_files.append(file)
                if file.extension in yapf_extensions:
                    yapf_input_files.append(file)
    if CcInfo in target:
        for file in target[CcInfo].compilation_context.direct_headers:
            if file.is_source and file.extension in clang_format_extensions:
                clang_format_input_files.append(file)

    output_files = []
    for input_file in clang_format_input_files:
        output_file = _run_clang_format(
            ctx,
            clang_format_config,
            clang_format_executable,
            input_file,
        )
        output_files.append(output_file)
    for input_file in yapf_input_files:
        output_file = _run_yapf(ctx, yapf_config, yapf_executable, input_file)
        output_files.append(output_file)

    return [OutputGroupInfo(report = depset(direct = output_files))]

def _clang_tidy_impl(target, ctx):
    if CcInfo not in target:
        return []

    clang_tidy_config = ctx.attr._clang_tidy_config.data_runfiles.files
    clang_tidy_executable = ctx.attr._clang_tidy_executable.files_to_run

    cc_toolchain = find_cpp_toolchain(ctx)
    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )
    cc_user_compile_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts
    cc_compile_variables = cc_common.create_compile_variables(
        feature_configuration = cc_feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = cc_user_compile_flags,
    )
    cc_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = cc_feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = cc_compile_variables,
    )
    rule_flags = getattr(ctx.rule.attr, "copts", [])
    flags = cc_flags + rule_flags

    compilation_context = target[CcInfo].compilation_context

    input_files = []
    for src in getattr(ctx.rule.attr, "srcs", []):
        input_files += [src for src in src.files.to_list() if src.is_source]

    output_files = []
    for input_file in input_files:
        output_file = _run_clang_tidy(
            ctx,
            clang_tidy_config,
            clang_tidy_executable,
            flags,
            compilation_context,
            input_file,
            target.label.name,
        )
        output_files.append(output_file)

    return [OutputGroupInfo(report = depset(direct = output_files))]

format = aspect(
    implementation = _clang_format_impl,
    attrs = {
        "_clang_format_executable": attr.label(
            default = Label("//toolchain/style:clang_format"),
        ),
        "_clang_format_config": attr.label(
            default = Label("//:clang_format_config"),
        ),
        "_yapf_executable": attr.label(
            default = Label("//toolchain/style:yapf"),
        ),
        "_yapf_config": attr.label(
            default = Label("//:yapf_config"),
        ),
    },
    doc = "Run Clang Format and apply changes.",
)

lint = aspect(
    implementation = _clang_tidy_impl,
    fragments = ["cpp"],
    attrs = {
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_clang_tidy_executable": attr.label(
            default = Label("//toolchain/style:clang_tidy"),
        ),
        "_clang_tidy_config": attr.label(
            default = Label("//:clang_tidy_config"),
        ),
    },
    doc = "Run Clang Tidy and report violations.",
)