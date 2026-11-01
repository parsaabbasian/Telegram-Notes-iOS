load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_test")

swift_library(
    name = "TelegramNotes",
    module_name = "TelegramNotes",
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
        "//submodules/InvisibleInkDustNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Host (macOS) test of the model: only that file is compiled, it needs nothing but Foundation.
# Run with `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramUI/Components/TelegramNotes:TelegramNoteModelTests`.
swift_test(
    name = "TelegramNoteModelTests",
    module_name = "TelegramNoteModelTests",
    srcs = [
        "Sources/TelegramNoteModel.swift",
        "Tests/TelegramNoteModelTests.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
)
