pub fn exec(io: std.Io, args: []const [:0]const u8) !void {
    switch (builtin.os.tag) {
        .linux => {},
        else => @compileError("watchfd is currently linux-only"),
    }

    if (args.len >= 2) {
        const pid = std.fmt.parseInt(posix.pid_t, args[1], 10) catch {
            std.debug.print("[-] invalid pid!\n", .{});
            return error.InvalidPid;
        };

        try trace(io, pid);
        return;
    }

    std.debug.print("[-] please provide a pid", .{});
}

fn trace(io: Io, pid: posix.pid_t) !void {
    const options: usize =
        linux.PTRACE.O.TRACESYSGOOD |
        linux.PTRACE.O.TRACEEXIT;

    const W_ALL: u32 = 0x40000000; // ziglint-ignore: Z006

    var outbuf: [4096]u8 = undefined;
    var outwriter = std.Io.File.stdout().writer(io, &outbuf);
    const stdout = &outwriter.interface;

    // clear screen and hide cursor
    try stdout.writeAll("\x1b[2J\x1b[H\x1b[?25l");
    try stdout.flush();

    // make sure cursor comes back when we exit
    defer {
        stdout.writeAll("\x1b[?25h\n") catch {};
        stdout.flush() catch {};
    }

    posix.ptrace(
        linux.PTRACE.SEIZE,
        pid,
        0,
        options,
    ) catch |err| switch (err) {
        error.PermissionDenied => {
            std.debug.print(
                "[-] ptrace attach denied; check /proc/sys/kernel/yama/ptrace_scope\n",
                .{},
            );
            return;
        },
        else => return err,
    };

    try posix.ptrace(
        linux.PTRACE.INTERRUPT,
        pid,
        0,
        0,
    );

    // initial stop
    while (true) {
        var status: u32 = undefined;
        const rc = linux.waitpid(pid, &status, W_ALL);

        switch (posix.errno(rc)) {
            .SUCCESS => {
                if (!linux.W.IFSTOPPED(status))
                    return error.UnexpectedTraceState;
                break;
            },
            .INTR => continue,
            .CHILD => return error.NoChildProcess,
            else => |err| return posix.unexpectedErrno(err),
        }
    }

    try drawProcFd(io, pid, stdout);

    try posix.ptrace(
        linux.PTRACE.SYSCALL,
        pid,
        0,
        0,
    );

    var syscall_entry = true;

    while (true) {
        var status: u32 = undefined;

        const rc = linux.waitpid(pid, &status, W_ALL);

        switch (posix.errno(rc)) {
            .SUCCESS => {},
            .INTR => continue,
            .CHILD => return,
            else => |err| return posix.unexpectedErrno(err),
        }

        const tid: posix.pid_t = @intCast(rc);

        if (linux.W.IFEXITED(status))
            return;

        if (linux.W.IFSIGNALED(status))
            return;

        if (!linux.W.IFSTOPPED(status))
            continue;

        const sig = @intFromEnum(linux.W.STOPSIG(status));

        const syscall_sig =
            @intFromEnum(posix.SIG.TRAP) | 0x80;

        if (sig == syscall_sig) {
            if (syscall_entry) {
                // syscall hasn't happened yet
                syscall_entry = false;
            } else {
                // syscall just completed
                syscall_entry = true;

                try drawProcFd(io, pid, stdout);
            }

            try posix.ptrace(
                linux.PTRACE.SYSCALL,
                tid,
                0,
                0,
            );

            continue;
        }

        const event = status >> 16;

        if (event != 0) {
            try posix.ptrace(
                linux.PTRACE.SYSCALL,
                tid,
                0,
                0,
            );

            continue;
        }

        // real sig we want to forward
        try posix.ptrace(
            linux.PTRACE.SYSCALL,
            tid,
            0,
            sig,
        );
    }
}

fn drawProcFd(io: Io, pid: posix.pid_t, stdout: *std.Io.Writer) !void {
    // cursor home and clear everything below cursor
    try stdout.writeAll("\x1b[H\x1b[J");

    try stdout.print("{s}watchfd{s} - pid {s}{d}{s}\n\n", .{
        ansi.bold ++ ansi.underline ++ ansi.red,
        ansi.reset,
        ansi.magenta,
        pid,
        ansi.reset,
    });

    var path_buf: [Io.Dir.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(
        &path_buf,
        "/proc/{d}/fd",
        .{pid},
    );

    var dir = try Io.Dir.openDirAbsolute(
        io,
        path,
        .{ .iterate = true },
    );
    defer dir.close(io);

    var it = dir.iterate();

    while (try it.next(io)) |entry| {
        const fd = std.fmt.parseInt(
            posix.fd_t,
            entry.name,
            10,
        ) catch continue;
        var target_buf: [Io.Dir.max_path_bytes]u8 = undefined;

        const len = dir.readLink(io, entry.name, &target_buf) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied,
            error.PermissionDenied,
            => {
                try stdout.print(
                    "{d: >3} -> permission denied\n",
                    .{fd},
                );
                continue;
            },
            else => return err,
        };
        try stdout.print("{s}{d: >3}{s} {s}->{s} {s}{s}{s}\n", .{
            ansi.bold ++ ansi.green,
            fd,
            ansi.reset,
            ansi.magenta,
            ansi.reset,
            ansi.yellow,
            target_buf[0..len],
            ansi.reset,
        });
    }
}

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const ansi = @import("ansi.zig");

const posix = std.posix;
const linux = std.os.linux;
