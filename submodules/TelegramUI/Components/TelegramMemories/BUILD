load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "TelegramMemories",
    module_name = "TelegramMemories",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/TelegramPresentationData",
        "//submodules/Display",
        "//submodules/AsyncDisplayKit",
        "//submodules/ComponentFlow",
        "//submodules/PhotoResources",
        "//submodules/AvatarNode",
        "//submodules/TelegramUI/Components/TelegramNotes",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test of the model: only that file is compiled, it needs nothing but Foundation.
# Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramUI/Components/TelegramMemories:TelegramMemoryModelTests`.
swift_test(
    name = "TelegramMemoryModelTests",
    module_name = "TelegramMemoryModelTests",
    srcs = [
        "Sources/TelegramMemoryModel.swift",
        "Tests/TelegramMemoryModelTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
