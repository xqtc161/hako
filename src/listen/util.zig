const std = @import("std");
const Io = std.Io;
const ansi = @import("../ansi.zig");

pub fn redir(io: Io, server: *Io.net.Server) !void {
    std.debug.print("{s}[+] listening{s}\n", .{ ansi.green ++ ansi.dim, ansi.reset });

    var stream = try server.accept(io);
    defer stream.close(io);

    std.debug.print("{s}[+] client connected{s}\n", .{ ansi.green ++ ansi.dim, ansi.reset });

    var recv_buf: [4 * 1024]u8 = undefined;
    var reader = stream.reader(io, &recv_buf);

    var outbuf: [4 * 1024]u8 = undefined;
    var outwriter = Io.File.stdout().writer(io, &outbuf);
    const stdout = &outwriter.interface;

    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| {
            switch (err) {
                error.EndOfStream => {
                    std.debug.print("{s}[*] client disconnected{s}\n", .{ ansi.green ++ ansi.dim, ansi.reset });
                    break;
                },
                else => {
                    std.debug.print("{s}[-] error:{s} {any}\n", .{ ansi.red ++ ansi.dim, ansi.reset, err });
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
