const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

pub fn exec(io: std.Io, args: []const [:0]const u8) !void {
    switch (builtin.os.tag) {
        .linux => {},
        else => @compileError("watchfd is currently linux-only"),
    }

    if (args.len >= 2) {
        const pid = std.fmt.parseInt(std.posix.pid_t, args[1], 10) catch {
            std.debug.print("[-] invalid pid!\n", .{});
            return error.InvalidPid;
        };

        try getProcFd(io, pid);
        return;
    }

    std.debug.print("[-] please provide a pid", .{});
}

fn getProcFd(io: std.Io, pid: std.posix.pid_t) !void {
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "/proc/{d}/fd",
        .{pid},
    );

    var dir = Io.Dir.openDirAbsolute(
        io,
        path,
        .{ .iterate = true },
    ) catch |e| {
        std.debug.print("[-] failed to open {s}!\n", .{path});
        return e;
    };
    defer dir.close(io);

    var it = dir.iterate();

    while (try it.next(io)) |entry| {
        const fd = std.fmt.parseInt(
            std.posix.fd_t,
            entry.name,
            10,
        ) catch continue;

        var target_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;

        const len = dir.readLink(io, entry.name, &target_buf) catch |err| {
            switch (err) {
                error.FileNotFound => continue, // fd most likely disappeared between readdir and readlink

                error.AccessDenied,
                error.PermissionDenied,
                => {
                    std.debug.print("[-] {d}: permission denied\n", .{fd});
                    continue;
                },

                else => return err,
            }
        };
        var outbuf: [4096]u8 = undefined;
        var outreader = std.Io.File.stdout().writer(io, &outbuf);
        const stdout = &outreader.interface;

        try stdout.print("{d: >3} -> {s}\n", .{ fd, target_buf[0..len] });
        try stdout.flush();
    }
    return;
}
