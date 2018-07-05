# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""An aspect that collects information about Swift usage among dependencies."""

load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo", "SwiftUsageInfo")

def _get_swift_toolchain(target, aspect_ctx):
    """Gets the `SwiftToolchainInfo` used to build the given target, if any.

    Args:
      target: The target being built.
      aspect_ctx: The aspect context.

    Returns:
      The `SwiftToolchainInfo` provider, or `None` if the target was not a Swift
      target.
    """
    if SwiftInfo in target:
        toolchain_target = getattr(aspect_ctx.rule.attr, "_toolchain")
        if toolchain_target and SwiftToolchainInfo in toolchain_target:
            return toolchain_target[SwiftToolchainInfo]
    return None

def _swift_usage_aspect_impl(target, aspect_ctx):
    # If the target itself propagates `SwiftInfo`, get the toolchain from it.
    found_toolchain = _get_swift_toolchain(target, aspect_ctx)

    if found_toolchain:
        return [SwiftUsageInfo(toolchain = found_toolchain)]

    # If one of the deps propagates `SwiftUsageInfo` provider, we can repropagate
    # that information.
    # TODO(allevato): We currently make the assumption that all Swift
    # dependencies are built with the same toolchain (as in Bazel toolchain, not
    # Swift toolchain).
    for dep in getattr(aspect_ctx.rule.attr, "deps", []):
        if SwiftUsageInfo in dep:
            return [dep[SwiftUsageInfo]]

    # Don't propagate the provider at all if the target nor its dependencies use
    # Swift.
    return []

swift_usage_aspect = aspect(
    attr_aspects = ["deps"],
    doc = """
Collects information about how Swift is used in a dependency tree.

When attached to an attribute, this aspect will propagate a `SwiftUsageInfo`
provider for any target found in that attribute that uses Swift, either directly
or deeper in its dependency tree. Conversely, if neither a target nor its
transitive dependencies use Swift, the `SwiftUsageInfo` provider will not be
propagated.

Specifically, the aspect propagates which toolchain was used to build those
dependencies. This information is typically always the same for any Swift
targets built in the same configuration, but this allows upstream targets that
may not be *strictly* Swift-related and thus don't want to depend directly on
the Swift toolchain (such as Apple universal binary linking rules) to avoid
doing so but still get access to information derived from the toolchain (like
which linker flags to pass to link to the runtime).

We use an aspect (as opposed to propagating this information through normal
providers returned by `swift_library`) because the information is needed if
Swift is used _anywhere_ in a dependency graph, even as dependencies of other
language rules that wouldn't know how to propagate the Swift-specific providers.
""",
    implementation = _swift_usage_aspect_impl,
)
