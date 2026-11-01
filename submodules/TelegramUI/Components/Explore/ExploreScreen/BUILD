load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library", "swift_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

swift_library(
    name = "ExploreScreen",
    module_name = "ExploreScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/PhotoResources",
        "//submodules/AvatarNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The ranking is Foundation-only and can be checked on the host without XCTest.
swift_binary(
    name = "ExploreSimilarityTestRunner",
    testonly = True,
    srcs = [
        "Sources/ExploreSimilarity.swift",
        "Sources/ExploreTogetherModel.swift",
        "Tests/main.swift",
    ],
    copts = ["-warnings-as-errors"],
)

sh_test(
    name = "ExploreSimilarityTests",
    srcs = ["Tests/run_similarity_tests.sh"],
    args = ["$(location :ExploreSimilarityTestRunner)"],
    data = [":ExploreSimilarityTestRunner"],
)
