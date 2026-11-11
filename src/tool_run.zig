const std = @import("std");
const r = @import("r4os");
const a = r.abi;
const records = r.diagnostics.core;

test "dialog owner tool output retains split UTF8 and unread bytes across backpressure" {
    const Output = struct {
        bytes: [64]u8 = undefined,
        used: usize = 0,
        fn accept(raw: ?*anyopaque, chunk: *const records.Chunk) callconv(.c) records.Ack {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            @memcpy(self.bytes[self.used..][0..chunk.length], chunk.data[0..chunk.length]);
            self.used += chunk.length;
            self.bytes[self.used] = '|';
            self.used += 1;
            return .{ .accepted_bytes = chunk.length };
        }
    };
    var memory: [24]u8 = undefined;
    var queue = try records.BoundedDiagnosticBuffer.init(&memory);
    var channel = Channel{ .pipe = undefined, .severity = .info };
    @memcpy(channel.input[0..2], "€"[0..2]);
    channel.input_count = 2;
    try channel.ingest(&queue);
    try std.testing.expectEqual(@as(usize, 2), channel.used);
    try std.testing.expectEqual(@as(u64, 0), (try queue.stats()).queued_records);
    const rest = "\xacA\nTwo\nThree\n";
    @memcpy(channel.input[0..rest.len], rest);
    channel.input_count = rest.len;
    channel.eof = true;
    try channel.ingest(&queue);
    try std.testing.expect(channel.pending != null);
    try std.testing.expect(channel.input_count != 0);
    var output = Output{};
    for (0..5) |_| {
        _ = try queue.flushOnce(64, Output.accept, &output);
        try channel.ingest(&queue);
    }
    try std.testing.expectEqualStrings("€A\n|Two\n|Three\n|", output.bytes[0..output.used]);
    try std.testing.expect(channel.done());
    try std.testing.expectEqual(@as(u64, 0), (try queue.stats()).queued_records);
    channel.used = 1;
    channel.line[0] = 0xc3;
    try std.testing.expectError(error.InvalidText, channel.ingest(&queue));
    try std.testing.expect(!channel.done());
}

const Channel = struct {
    pipe: r.byte_pipe.Pair,
    severity: records.Severity,
    input: [512]u8 = undefined,
    input_count: usize = 0,
    input_at: usize = 0,
    line: [1024]u8 = undefined,
    used: usize = 0,
    pending: ?usize = null,
    eof: bool = false,
    bytes: u64 = 0,

    fn enqueue(self: *Channel, queue: *records.BoundedDiagnosticBuffer) !bool {
        const count = self.pending orelse return true;
        const admitted = try queue.appendRecord(self.line[0..count], self.severity);
        if (admitted.kind == @intFromEnum(records.AppendKind.full)) return false;
        if (admitted.kind != @intFromEnum(records.AppendKind.accepted)) return error.RecordCapacity;
        std.mem.copyForwards(u8, self.line[0 .. self.used - count], self.line[count..self.used]);
        self.used -= count;
        self.pending = null;
        return true;
    }

    fn ingest(self: *Channel, queue: *records.BoundedDiagnosticBuffer) !void {
        if (!try self.enqueue(queue)) return;
        while (self.input_at < self.input_count) {
            if (self.used == self.line.len) {
                var whole = self.used;
                while (whole > 0 and !std.unicode.utf8ValidateSlice(self.line[0..whole])) whole -= 1;
                if (whole == 0 or self.used - whole > 3) return error.InvalidOutput;
                self.pending = whole;
                if (!try self.enqueue(queue)) return;
            }
            const byte = self.input[self.input_at];
            self.input_at += 1;
            self.line[self.used] = byte;
            self.used += 1;
            if (byte == '\n') {
                self.pending = self.used;
                if (!try self.enqueue(queue)) return;
            }
        }
        self.input_at = 0;
        self.input_count = 0;
        if (self.eof and self.used != 0) {
            self.pending = self.used;
            _ = try self.enqueue(queue);
        }
    }

    fn pump(self: *Channel, queue: *records.BoundedDiagnosticBuffer) !void {
        try self.ingest(queue);
        if (self.pending != null or self.input_count != 0 or self.eof) return;
        var progress: r.byte_pipe.Progress = .{};
        const rc = self.pipe.reader.read(&self.input, .{}, &progress);
        if (rc != 0 or progress.version != 1 or progress.size != @sizeOf(r.byte_pipe.Progress) or
            progress.flags != 0 or progress.bytes > self.input.len) return error.PipeRead;
        if (progress.state != a.byte_pipe_ready and progress.state != a.byte_pipe_would_block and
            progress.state != a.byte_pipe_eof) return error.PipeState;
        self.input_count = @intCast(progress.bytes);
        self.bytes += progress.bytes;
        self.eof = progress.state == a.byte_pipe_eof;
        try self.ingest(queue);
    }

    fn done(self: *const Channel) bool {
        return self.eof and self.input_count == 0 and self.used == 0 and self.pending == null;
    }

    fn close(self: *Channel) bool {
        const writer = self.pipe.writer.close();
        const reader = self.pipe.reader.close();
        return writer == 0 and reader == 0;
    }
};

pub const Result = struct {
    completion: a.ProgramProcessCompletion,
    io_error: i32,
    stdout_bytes: u64,
    stderr_bytes: u64,
};

/// Owned by the stable R4CODE main frame. Poll never retains its output sink.
/// A readiness event is followed by the real completion and consuming Reap.
pub const Run = struct {
    child: a.ProgramProcessHandle = .{},
    out: ?Channel = null,
    err: ?Channel = null,
    waits: ?r.wait_set.Set = null,
    completion: ?a.ProgramProcessCompletion = null,
    limit: ?r.rpc_budget.Budget = null,
    stop_limit: ?r.rpc_budget.Budget = null,
    kill_requested: bool = false,
    queue: ?records.BoundedDiagnosticBuffer = null,
    storage: [8192]u8 = undefined,
    failure: i32 = 0,
    reported: bool = false,

    pub fn active(self: *const Run) bool {
        return self.child.instance_id != 0 or self.out != null or self.err != null or self.waits != null;
    }

    fn closeUnused(self: *Run) bool {
        var closed = true;
        if (self.out) |*channel| {
            if (!channel.close()) closed = false;
        }
        if (self.err) |*channel| {
            if (!channel.close()) closed = false;
        }
        if (self.waits) |*waits| {
            _ = waits.close();
            if (waits.handle != 0) closed = false;
        }
        if (closed) {
            self.out = null;
            self.err = null;
            self.waits = null;
        }
        return closed;
    }

    pub fn start(self: *Run, context: *const r.platform2.Context, path: [*:0]const u8, args: [*:0]const u8, pipe_capacity: u64) i32 {
        if (self.active()) return a.launch_io_error_invalid;
        self.* = .{};
        self.queue = records.BoundedDiagnosticBuffer.init(&self.storage) catch return a.launch_io_error_invalid;
        const clock = r.platform2.abi.function(r.platform2.abi.R4SysFns2, context.system(), "monotonic_clock");
        self.limit = r.rpc_budget.Budget.fromTimeout(clock, r.time_contract.timeoutFinite(.{ .nanoseconds = 60_000_000_000 })) catch |err| return r.rpc_budget.code(err);
        var waits: r.wait_set.Set = undefined;
        var rc = r.wait_set.Set.init(context, 1, &waits);
        if (rc != 0) return rc;
        self.waits = waits;
        var out: r.byte_pipe.Pair = undefined;
        rc = r.byte_pipe.create(context, pipe_capacity, &out);
        if (rc != 0) {
            _ = self.closeUnused();
            return rc;
        }
        self.out = .{ .pipe = out, .severity = .info };
        var err: r.byte_pipe.Pair = undefined;
        rc = r.byte_pipe.create(context, pipe_capacity, &err);
        if (rc != 0) {
            _ = self.closeUnused();
            return rc;
        }
        self.err = .{ .pipe = err, .severity = .err };
        rc = r.launch_io.launch(context, path, args, .{
            .stdout_binding = r.launch_io.pipeBinding(out.writer.value),
            .stderr_binding = r.launch_io.pipeBinding(err.writer.value),
        }, &self.child);
        if (rc != 0) {
            _ = self.closeUnused();
            return rc;
        }
        // From admission onward Poll/shutdown retain every owned identity.
        var source: r.wait_set.Source = undefined;
        var registration: u64 = 0;
        rc = r.wait_set.prepare(context, r.wait_set.process(self.child, 1), &source);
        if (rc == 0) rc = self.waits.?.enroll(source, &registration);
        if (rc != 0) self.failure = rc;
        if (self.out.?.pipe.writer.close() != 0 or self.err.?.pipe.writer.close() != 0) self.failure = a.byte_pipe_error_invalid;
        return 0;
    }

    fn flush(self: *Run, sink: records.Sink, sink_context: ?*anyopaque) void {
        const queue = if (self.queue) |*value| value else return;
        for (0..4) |_| {
            const result = queue.flushOnce(4096, sink, sink_context) catch {
                self.failure = a.launch_io_error_invalid;
                return;
            };
            if (result.kind == @intFromEnum(records.FlushKind.empty) or result.kind == @intFromEnum(records.FlushKind.would_block)) return;
            if (result.kind != @intFromEnum(records.FlushKind.progress)) {
                self.failure = a.launch_io_error_invalid;
                return;
            }
        }
    }

    pub fn poll(self: *Run, sys: r.r4sys.Context, sink: records.Sink, sink_context: ?*anyopaque) ?Result {
        if (!self.active() or self.reported) return null;
        if (self.child.instance_id == 0 and self.completion == null) {
            _ = self.closeUnused();
            return null;
        }
        if (self.limit) |*limit| {
            if ((limit.remainingTicks() catch 0) == 0 and self.failure == 0) self.failure = a.launch_io_error_invalid;
        }
        self.flush(sink, sink_context);
        if (self.out) |*channel| {
            _ = channel.pipe.writer.close();
            channel.pump(&self.queue.?) catch {
                self.failure = a.byte_pipe_error_invalid;
            };
        }
        if (self.err) |*channel| {
            _ = channel.pipe.writer.close();
            channel.pump(&self.queue.?) catch {
                self.failure = a.byte_pipe_error_invalid;
            };
        }
        self.flush(sink, sink_context);
        if (self.child.instance_id != 0) {
            if (self.failure != 0) {
                _ = sys.programHandleRequestClose(&self.child);
                if (self.stop_limit == null) self.stop_limit = r.rpc_budget.Budget.fromTimeout(self.limit.?.clock, r.time_contract.timeoutFinite(.{ .nanoseconds = 500_000_000 })) catch null;
                if (self.stop_limit) |*limit| {
                    if ((limit.remainingTicks() catch 0) == 0) {
                        if (!self.kill_requested and sys.programHandleKill(&self.child) == 0) self.kill_requested = true;
                    }
                }
            }
            if (self.waits) |*waits| {
                var events: [1]r.wait_set.Event = undefined;
                var batch: r.wait_set.Batch = .{};
                if (waits.wait(.{}, &events, &batch) != 0) self.failure = a.waitset_error_invalid;
            }
            var completion: a.ProgramProcessCompletion = .{};
            if (sys.programHandleWait(&self.child, 0, &completion) == 0) {
                if (completion.sequence == 0 or completion.flags & a.program_completion_flag_ready == 0 or
                    completion.reserved0 != 0 or !std.meta.eql(completion.handle, self.child))
                {
                    self.failure = a.program_handle_error_invalid;
                    return null;
                }
                self.completion = completion;
            }
        }
        const completion = self.completion orelse return null;
        if (self.failure != 0) {
            _ = self.queue.?.discard() catch return null;
            inline for (.{ "out", "err" }) |name| {
                if (@field(self, name)) |*channel| {
                    channel.input_count = 0;
                    channel.input_at = 0;
                    channel.pending = null;
                    channel.used = 0;
                    channel.eof = true;
                }
            }
        }
        if (!self.out.?.done() or !self.err.?.done()) return null;
        const stats = self.queue.?.stats() catch return null;
        if (stats.queued_records != 0) return null;
        if (self.child.instance_id != 0) {
            var reaped: a.ProgramProcessCompletion = .{};
            if (sys.programHandleReap(&self.child, &reaped) != 0) return null;
            if (!std.meta.eql(reaped.handle, completion.handle) or reaped.sequence != completion.sequence) self.failure = a.program_handle_error_invalid;
            self.child = .{};
        }
        const result = Result{ .completion = completion, .io_error = self.failure, .stdout_bytes = self.out.?.bytes, .stderr_bytes = self.err.?.bytes };
        if (!self.closeUnused()) return null;
        self.reported = true;
        return result;
    }

    fn discard(_: ?*anyopaque, chunk: *const records.Chunk) callconv(.c) records.Ack {
        return .{ .accepted_bytes = chunk.length };
    }

    pub fn shutdown(self: *Run, sys: r.r4sys.Context) bool {
        if (!self.active()) return true;
        if (self.child.instance_id == 0 and self.completion == null) return self.closeUnused();
        _ = sys.programHandleRequestClose(&self.child);
        const clock = self.limit.?.clock;
        var grace = r.rpc_budget.Budget.fromTimeout(clock, r.time_contract.timeoutFinite(.{ .nanoseconds = 500_000_000 })) catch return false;
        var finish = r.rpc_budget.Budget.fromTimeout(clock, r.time_contract.timeoutFinite(.{ .nanoseconds = 10_000_000_000 })) catch return false;
        var killed = false;
        while (self.active()) {
            _ = self.poll(sys, discard, null);
            if (!self.active()) return true;
            _ = finish.remainingTicks() catch return false;
            if (!killed) {
                if ((grace.remainingTicks() catch 0) == 0) {
                    if (self.child.instance_id != 0) _ = sys.programHandleKill(&self.child);
                    killed = true;
                }
            }
            sys.sleepTicks(1);
        }
        return true;
    }
};
