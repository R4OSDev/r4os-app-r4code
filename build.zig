const std = @import("std");

/// Eigenstaendiger Bau aus dem Manifest.
pub fn build(b: *std.Build) void {
    const sdk_build = b.lazyImport(@This(), "r4os_sdk") orelse return;
    const sdk_dep = b.dependencyFromBuildZig(sdk_build, .{});
    const sdk = sdk_build.sdk(b, sdk_dep, .{});
    _ = sdk.addR4MF(b.path("module.R4MF"));
    _ = sdk.addR4MFWithOptions(b.path("Tests/DialogText/module.R4MF"), .{ .zig_module_roots = &.{b.path("src/main.zig")} });
    const host = sdk.createR4osModule(b.graph.host, .ReleaseSafe);
    const root = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = b.graph.host, .optimize = .ReleaseSafe });
    root.addImport("r4os", host);
    const cases = b.addTest(.{ .root_module = root, .filters = &.{"dialog owner"} });
    b.step("test", "Actual app dialog codepoint, preload and failed-save boundaries").dependOn(&b.addRunArtifact(cases).step);
}
