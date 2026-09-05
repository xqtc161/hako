const std = @import("std");
const Io = std.Io;

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    if (args.len < 2 or args.len != 3) {
        std.debug.print(
            "usage: hako listen unix <path>\n",
            .{},
        );
        return error.InvalidArguments;
    }

    var unix_path: ?[]const u8 = null;

    var server = blk: {
        const address: Io.net.UnixAddress = try .init(args[2]);

        const s = try address.listen(io, .{});

        unix_path = args[2];

        break :blk s;
    };

    defer {
        server.deinit(io);

        if (unix_path) |path|
            Io.Dir.cwd().deleteFile(io, path) catch {};
    }

    std.debug.print("[+] listening\n", .{});

    var stream = try server.accept(io);
    defer stream.close(io);

    std.debug.print("[+] client connected\n", .{});

    var recv_buf: [4 * 1024]u8 = undefined;
    var reader = stream.reader(io, &recv_buf);

    var outbuf: [4 * 1024]u8 = undefined;
    var outwriter = Io.File.stdout().writer(io, &outbuf);
    const stdout = &outwriter.interface;

    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| {
            switch (err) {
                error.EndOfStream => {
                    std.debug.print("[*] client disconnected\n", .{});
                    break;
                },
                else => {
                    std.debug.print("[-] error: {any}\n", .{err});
                    break;
                },
            }
        };
        const line_trimmed = std.mem.trim(u8, line, "\r\n \t");
        if (line_trimmed.len == 0) continue;
        try stdout.writeAll(line);
        try stdout.flush();
    }
}
