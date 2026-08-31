const std = @import("std");
const builtins = @import("builtin");

const watchfd = switch (builtins.os.tag) {
    .linux => @import("watchfd.zig"), // ziglint-ignore: Z028
    else => @compileError("unsupported OS"),
};
const dumpfd = switch (builtins.os.tag) {
    .linux => @import("dumpfd.zig"), // ziglint-ignore: Z028
    else => @compileError("unsupported OS"),
};
const listen = @import("listen.zig");
const pwait = @import("pwait.zig");
const when = @import("when.zig");
const ports = @import("ports.zig");

const ansi = @import("ansi.zig");

const Command = enum {
    watchfd,
    dumpfd,
    listen,
    pwait,
    when,
    ports,
    hako,

    fn fromString(str: []const u8) !Command {
        if (std.mem.eql(u8, str, "watchfd"))
            return .watchfd;
        if (std.mem.eql(u8, str, "dumpfd"))
            return .dumpfd;
        if (std.mem.eql(u8, str, "listen"))
            return .listen;
        if (std.mem.eql(u8, str, "pwait"))
            return .pwait;
        if (std.mem.eql(u8, str, "when"))
            return .when;
        if (std.mem.eql(u8, str, "ports"))
            return .ports;
        if (std.mem.eql(u8, str, "hako"))
            return .hako;
        std.debug.print("Expected command got: {s}\n", .{str});
        return error.FuckedUp;
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const basename = std.Io.Dir.path.basename(args[0]);

    const io = init.io;

    var inbuf: [1024]u8 = undefined;
    var inreader = std.Io.File.stdin().reader(init.io, &inbuf);
    const stdin = &inreader.interface;
    _ = stdin; // autofix

    var outbuf: [1024]u8 = undefined;
    var outreader = std.Io.File.stdout().writer(init.io, &outbuf);
    const stdout = &outreader.interface;

    switch (try Command.fromString(basename)) {
        .hako => {
            try printHako(stdout);
        },
        .watchfd => try watchfd.exec(io, args),
        .dumpfd => try dumpfd.exec(io, args),
        .listen => try listen.exec(io, args),
        .pwait => {},
        .when => {},
        .ports => {},
    }
    return;
}

fn printHako(stdout: *std.Io.Writer) !void {
    try stdout.print(
        \\{s}{s}{s}hako{s} - {s}{s}multicall, userland util{s}
        \\
        \\    {s}{s}commands:{s}
        \\
    , .{
        ansi.bold,
        ansi.yellow,
        ansi.underline,
        ansi.reset,

        ansi.dim,
        ansi.green,
        ansi.reset,

        ansi.green,
        ansi.underline,
        ansi.reset,
    });

    try stdout.print(
        \\        {s}watchfd{s} - {s}inspect file descriptors of a process in a refreshing view{s}
        \\        {s}dumpfd{s}  - {s}inspect a snapshot of file descriptors of a given process{s}
        \\        {s}listen{s}  - {s}tcp/unix sockets{s}
        \\        {s}pwait{s}   - {s}wait for a proc to disappear{s}
        \\        {s}when{s}    - {s}execute a command when a file/directory changes{s}
        \\        {s}ports{s}   - {s}print ports and the processes that listen on them{s}
        \\
    , .{
        ansi.underline,
        ansi.reset,
        ansi.green,
        ansi.reset,

        ansi.underline,
        ansi.reset,
        ansi.green,
        ansi.reset,

        ansi.underline,
        ansi.reset,
        ansi.green,
        ansi.reset,

        ansi.underline,
        ansi.reset,
        ansi.green,
        ansi.reset,

        ansi.underline,
        ansi.reset,
        ansi.green,
        ansi.reset,

        ansi.underline,
        ansi.reset,
        ansi.green,
        ansi.reset,
    });

    try stdout.print(
        \\
        \\    {s}{s}source{s}: https://git.sr.ht/~xqtc/hako
        \\
        \\    {s}{s}license{s}: MIT
        \\
        \\
    , .{
        ansi.green,
        ansi.underline,
        ansi.reset,

        ansi.green,
        ansi.underline,
        ansi.reset,
    });

    try stdout.print(
        \\{s}{s}{s}TRANS RIGHTS ARE HUMAN RIGHTS!{s}
    , .{
        ansi.magenta,
        ansi.underline,
        ansi.bold,
        ansi.reset,
    });
    stdout.flush() catch return;
}
