const std = @import("std");
const Io = std.Io;

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    var server = blk: {
        const address = try argsFromSlice(io, args);
        break :blk try address.listen(io, .{
            .reuse_address = true,
        });
    };

    defer server.deinit(io);

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

fn argsFromSlice(io: Io, args: []const [:0]const u8) !Io.net.IpAddress {
    if (args.len < 2 or args.len != 4) {
        std.debug.print(
            "usage: hako listen tcp <address> <port>\n",
            .{},
        );
        return error.InvalidArguments;
    }
    const port = std.fmt.parseInt(u16, args[3], 10) catch return error.InvalidPort;
    const address = try resolveTcpAddress(
        io,
        args[2],
        port,
    );
    return address;
}

fn resolveTcpAddress(
    io: Io,
    host: []const u8,
    port: u16,
) !Io.net.IpAddress {
    if (std.mem.eql(u8, host, "*"))
        return .{ .ip4 = .unspecified(port) };

    if (Io.net.IpAddress.resolve(io, host, port)) |address| {
        return address;
    } else |_| {}

    const hostname: Io.net.HostName = try .init(host);

    var canonical_name_buffer: [Io.net.HostName.max_len]u8 = undefined;
    var result_buffer: [16]Io.net.HostName.LookupResult = undefined;
    var results: Io.Queue(Io.net.HostName.LookupResult) =
        .init(&result_buffer);

    try hostname.lookup(io, &results, .{
        .port = port,
        .canonical_name_buffer = &canonical_name_buffer,
    });

    while (results.getOne(io)) |result| {
        switch (result) {
            .address => |address| return address,
            .canonical_name => {},
        }
    } else |err| switch (err) {
        error.Closed => return error.UnknownHostName,
        error.Canceled => return err,
    }
}
