const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("tracy.zig");
const assert = std.debug.assert;
const c = @cImport({
    @cInclude("sqlite3.h");
});

const DB_DIR = "resource/db";
const READ_FLAGS = std.fs.File.OpenFlags{ .mode = std.fs.File.OpenMode.read_only };
const WRITE_FLAGS = std.fs.File.OpenFlags{ .mode = std.fs.File.OpenMode.write_only };

const logger = std.log.scoped(.model);

fn logErr(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        logger.err(fmt, args);
    } else {
        logger.info(fmt, args);
    }
}

fn parsedOptionalValue(parsed_result: anyerror!?[]u8) ?[]u8 {
    if (parsed_result) |maybe_value| {
        return maybe_value;
    } else |err| {
        std.debug.panic("parsed_result was an error {!}\n", .{err});
    }
}

fn parsedValue(parsed_result: anyerror!?[]u8) []u8 {
    if (parsedOptionalValue(parsed_result)) |value| {
        return value;
    } else {
        std.debug.panic("parsed value was null\n", .{});
    }
}

pub const Sqlite = struct {
    db: *c.sqlite3,
    select_contacts_by_user_stmt: *c.sqlite3_stmt = undefined,
    update_contact_stmt: *c.sqlite3_stmt = undefined,
    insert_contact_stmt: *c.sqlite3_stmt = undefined,
    insert_user_stmt: *c.sqlite3_stmt = undefined,
    select_users_stmt: *c.sqlite3_stmt = undefined,
    select_user_by_external_id_stmt: *c.sqlite3_stmt = undefined,
    select_webhook_stmt: *c.sqlite3_stmt = undefined,

    pub const Env = enum {
        prod,
        testing,

        pub fn dbPath(self: Env) [*:0]const u8 {
            return switch (self) {
                .prod => DB_DIR ++ "/dont_be_strangers.sqlite3",
                .testing => DB_DIR ++ "/test.sqlite3",
            };
        }
    };

    fn init(db: *c.sqlite3) !Sqlite {
        const select_contacts_by_user_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ SELECT
                \\     id,
                \\     user_id,
                \\     full_name,
                \\     frequency_days,
                \\     due_at
                \\ FROM
                \\     contacts
                \\ WHERE user_id = ?1
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create select_contacts_by_user_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };

        const update_contact_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ UPDATE contacts
                \\ SET
                \\     full_name = ?1,
                \\     frequency_days = ?2,
                \\     due_at = ?3
                \\ WHERE
                \\     id = ?4
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create update_contact_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };

        const insert_contact_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ INSERT INTO contacts
                \\     (user_id, full_name, frequency_days, due_at)
                \\ VALUES
                \\     (?1, ?2, ?3, ?4)
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create insert_contact_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };

        const insert_user_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ INSERT OR IGNORE INTO users
                \\     (external_id, login, authenticator)
                \\ VALUES
                \\     (?1, ?2, ?3)
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create insert_user_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };

        const select_users_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ SELECT
                \\     id,
                \\     external_id,
                \\     login,
                \\     authenticator
                \\ FROM
                \\     users
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create select_users_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };


        const select_user_by_external_id_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ SELECT
                \\     id,
                \\     external_id,
                \\     login,
                \\     authenticator
                \\ FROM
                \\     users
                \\ WHERE external_id = ?1
                \\     AND authenticator = ?2
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create select_user_by_external_id_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };

        const select_webhook_stmt = blk: {
            var stmt: ?*c.sqlite3_stmt = undefined;
            const sql =
                \\ SELECT
                \\     id,
                \\     user_id,
                \\     url,
                \\     hook_for
                \\ FROM
                \\     webhooks
                \\ WHERE user_id = ?1
                \\     AND hook_for = ?2
            ;
            if (c.SQLITE_OK != c.sqlite3_prepare_v2(db, sql, sql.len + 1, &stmt, null)) {
                logErr("Failed to create select_webhook_stmt statement {s}: {s}", .{sql, c.sqlite3_errmsg(db)});
                return error.CreateStmtFailure;
            }
            break :blk stmt.?;
        };

        _ = c.sqlite3_busy_timeout(db, 3000);

        return .{
            .db = db,
            .select_contacts_by_user_stmt = select_contacts_by_user_stmt,
            .update_contact_stmt = update_contact_stmt,
            .insert_contact_stmt = insert_contact_stmt,
            .insert_user_stmt = insert_user_stmt,
            .select_users_stmt = select_users_stmt,
            .select_user_by_external_id_stmt = select_user_by_external_id_stmt,
            .select_webhook_stmt = select_webhook_stmt,
        };
    }

    pub fn open(env: Sqlite.Env) !Sqlite {
        var db_ptr: ?*c.sqlite3 = undefined;
        const path = env.dbPath();
        const open_result = c.sqlite3_open(path, &db_ptr);
        if (open_result != c.SQLITE_OK) {
            logErr("Failed to open sqlite DB {s}: {s}", .{path, c.sqlite3_errmsg(db_ptr)});
            return error.DbOpenFailure;
        }
        return Sqlite.init(db_ptr.?);
    }

    pub fn deinit(self: Sqlite) void {
        _ = c.sqlite3_finalize(self.select_contacts_by_user_stmt);
        _ = c.sqlite3_finalize(self.update_contact_stmt);
        _ = c.sqlite3_finalize(self.insert_contact_stmt);
        _ = c.sqlite3_finalize(self.insert_user_stmt);
        _ = c.sqlite3_finalize(self.select_users_stmt);
        _ = c.sqlite3_finalize(self.select_user_by_external_id_stmt);
        _ = c.sqlite3_finalize(self.select_webhook_stmt);
        _ = c.sqlite3_close(self.db);
    }

    fn execute(self: Sqlite, sql: [*:0]const u8) !void {
        var err_msg: [*c]u8 = undefined;
        const exec_result = c.sqlite3_exec(self.db, sql, null, null, &err_msg);
        if (exec_result != c.SQLITE_OK) {
            defer c.sqlite3_free(err_msg);
            logErr("Failed to exec sql '{s}': {s}", .{sql, err_msg});
            return error.DbExecFailure;
        }
    }

    pub fn setup() !void {
        var db_ptr: ?*c.sqlite3 = undefined;
        const path = Env.prod.dbPath();
        const open_result = c.sqlite3_open(path, &db_ptr);
        defer {
            _ = c.sqlite3_close(db_ptr);
        }
        if (open_result != c.SQLITE_OK) {
            logErr("Failed to open sqlite DB during setup {s}: {s}", .{path, c.sqlite3_errmsg(db_ptr)});
            return error.DbOpenFailure;
        }

        const sql =
            \\ CREATE TABLE IF NOT EXISTS users (
            \\   id INTEGER NOT NULL,
            \\   external_id TEXT NOT NULL,
            \\   login TEXT NOT NULL,
            \\   authenticator TEXT NOT NULL,
            \\   PRIMARY KEY (id ASC),
            \\   UNIQUE (external_id, authenticator)
            \\ );
            \\
            \\ CREATE TABLE IF NOT EXISTS contacts (
            \\   id INTEGER NOT NULL,
            \\   user_id INTEGER NOT NULL,
            \\   full_name TEXT NOT NULL,
            \\   frequency_days INTEGER NOT NULL,
            \\   due_at INTEGER NOT NULL,
            \\   PRIMARY KEY (id ASC),
            \\   FOREIGN KEY (user_id) REFERENCES users(id)
            \\ );
            \\
            \\ CREATE TABLE IF NOT EXISTS webhooks (
            \\   id INTEGER NOT NULL,
            \\   user_id INTEGER NOT NULL,
            \\   url TEXT NOT NULL,
            \\   hook_for TEXT NOT NULL,
            \\   PRIMARY KEY (id ASC),
            \\   FOREIGN KEY (user_id) REFERENCES users(id),
            \\   UNIQUE (user_id, hook_for)
            \\ );
        ;

        const self = Sqlite{ .db = db_ptr.? };

        try self.execute(sql);
    }

    pub fn setupTest() !void {
        var db_ptr: ?*c.sqlite3 = undefined;
        const path = Env.testing.dbPath();
        const open_result = c.sqlite3_open(path, &db_ptr);
        defer {
            _ = c.sqlite3_close(db_ptr);
        }
        if (open_result != c.SQLITE_OK) {
            logErr("Failed to open sqlite DB during setupTest {s}: {s}", .{path, c.sqlite3_errmsg(db_ptr)});
            return error.DbOpenFailure;
        }

        const sql =
            \\ DROP TABLE IF EXISTS users;
            \\ DROP TABLE IF EXISTS contacts;
            \\ DROP TABLE IF EXISTS webhooks;
            \\
            \\ CREATE TABLE IF NOT EXISTS users (
            \\   id INTEGER NOT NULL,
            \\   external_id TEXT NOT NULL,
            \\   login TEXT NOT NULL,
            \\   authenticator TEXT NOT NULL,
            \\   PRIMARY KEY (id ASC),
            \\   UNIQUE (external_id, authenticator)
            \\ );
            \\
            \\ CREATE TABLE IF NOT EXISTS contacts (
            \\   id INTEGER NOT NULL,
            \\   user_id INTEGER NOT NULL,
            \\   full_name TEXT NOT NULL,
            \\   frequency_days INTEGER NOT NULL,
            \\   due_at INTEGER NOT NULL,
            \\   PRIMARY KEY (id ASC),
            \\   FOREIGN KEY (user_id) REFERENCES users(id)
            \\ );
            \\
            \\ CREATE TABLE IF NOT EXISTS webhooks (
            \\   id INTEGER NOT NULL,
            \\   user_id INTEGER NOT NULL,
            \\   url TEXT NOT NULL,
            \\   hook_for TEXT NOT NULL,
            \\   PRIMARY KEY (id ASC),
            \\   FOREIGN KEY (user_id) REFERENCES users(id),
            \\   UNIQUE (user_id, hook_for)
            \\ );
            \\
            \\ INSERT INTO users
            \\     (external_id, login, authenticator)
            \\ VALUES
            \\     ('1', 'nathan_dummy', 'github'),
            \\     ('abc_dummy', 'test_dummy', 'github');
            \\
            \\ WITH user AS (
            \\     SELECT id as user_id FROM users WHERE external_id = '1' AND authenticator = 'github'
            \\ )
            \\ INSERT INTO contacts
            \\     (user_id, full_name, frequency_days, due_at)
            \\ SELECT user_id, 'Bob', 1, 86401 FROM user
            \\ UNION ALL
            \\ SELECT user_id, 'Timmy', 14, 120000 FROM user;
        ;

        const self = Sqlite{ .db = db_ptr.? };

        try self.execute(sql);
    }

    pub fn selectContactsByUser(self: Sqlite, alloc: std.mem.Allocator, user_id_input: i64) !ContactList {
        defer {
            _ = c.sqlite3_reset(self.select_contacts_by_user_stmt);
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.select_contacts_by_user_stmt, 1, @intCast(user_id_input))) {
            logErr("Failed to bind user_id: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        var contact_list = ContactList.init(alloc);

        var step_result = c.sqlite3_step(self.select_contacts_by_user_stmt);
        while (step_result == c.SQLITE_ROW) : (step_result = c.sqlite3_step(self.select_contacts_by_user_stmt)) {
            const id = c.sqlite3_column_int64(self.select_contacts_by_user_stmt, 0);
            const user_id = c.sqlite3_column_int64(self.select_contacts_by_user_stmt, 1);
            const full_name = c.sqlite3_column_text(self.select_contacts_by_user_stmt, 2);
            const full_name_len: usize = @intCast(c.sqlite3_column_bytes(self.select_contacts_by_user_stmt, 2));
            const frequency_days = c.sqlite3_column_int(self.select_contacts_by_user_stmt, 3);
            const due_at = c.sqlite3_column_int64(self.select_contacts_by_user_stmt, 4);

            const full_name_buf = try alloc.alloc(u8, full_name_len);
            errdefer alloc.free(full_name_buf);
            // full_name is a [:0]const u8, we don't want the null byte at the end copied.
            // full_name_len doesn't count the null byte at the end.
            @memcpy(full_name_buf, full_name[0..full_name_len]);

            var contact = Contact.init(alloc);
            contact.id = @as(i64, id);
            contact.user_id = @as(i64, user_id);
            contact.full_name = full_name_buf;
            contact.frequency_days = @intCast(frequency_days);
            contact.due_at = @intCast(due_at);

            try contact_list.put(contact.id.?, contact);
        }

        if (c.SQLITE_DONE != step_result) {
            logErr("Step in selectContactsByUser failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return contact_list;
    }

    pub fn updateContact(self: Sqlite, alloc: std.mem.Allocator, contact: Contact) !void {
        defer {
            _ = c.sqlite3_reset(self.update_contact_stmt);
        }

        const full_name_c = try std.fmt.allocPrintZ(alloc, "{s}", .{contact.full_name});
        defer alloc.free(full_name_c);
        // SQLITE_STATIC means that dont_be_strangers is responsible for deallocating full_name_c.
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.update_contact_stmt, 1, full_name_c, @intCast(full_name_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind full_name: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.update_contact_stmt, 2, @intCast(contact.frequency_days))) {
            logErr("Failed to bind frequency_days: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.update_contact_stmt, 3, @intCast(contact.due_at))) {
            logErr("Failed to bind due_at: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.update_contact_stmt, 4, @intCast(contact.id.?))) {
            logErr("Failed to bind id: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        if (c.SQLITE_DONE != c.sqlite3_step(self.update_contact_stmt)) {
            logErr("Step in updateContact failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return;
    }

    pub fn insertContact(self: Sqlite, alloc: std.mem.Allocator, contact: Contact) !void {
        defer {
            _ = c.sqlite3_reset(self.insert_contact_stmt);
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.insert_contact_stmt, 1, @intCast(contact.user_id))) {
            logErr("Failed to bind user_id: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        const full_name_c = try std.fmt.allocPrintZ(alloc, "{s}", .{contact.full_name});
        defer alloc.free(full_name_c);
        // SQLITE_STATIC means that dont_be_strangers is responsible for deallocating full_name_c.
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.insert_contact_stmt, 2, full_name_c, @intCast(full_name_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind full_name: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.insert_contact_stmt, 3, @intCast(contact.frequency_days))) {
            logErr("Failed to bind frequency_days: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.insert_contact_stmt, 4, @intCast(contact.due_at))) {
            logErr("Failed to bind due_at: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindIntFailure;
        }

        if (c.SQLITE_DONE != c.sqlite3_step(self.insert_contact_stmt)) {
            logErr("Step in insertContact failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return;
    }

    pub fn insertOrIgnoreUser(self: Sqlite, alloc: std.mem.Allocator, external_id: []const u8, login: []const u8, authenticator: Authenticator) !void {
        defer {
            _ = c.sqlite3_reset(self.insert_user_stmt);
        }

        const external_id_c = try std.fmt.allocPrintZ(alloc, "{s}", .{external_id});
        defer alloc.free(external_id_c);
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.insert_user_stmt, 1, external_id_c, @intCast(external_id_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind external_id: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        const login_c = try std.fmt.allocPrintZ(alloc, "{s}", .{login});
        defer alloc.free(login_c);
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.insert_user_stmt, 2, login_c, @intCast(login_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind login: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        const authenticator_c = authenticator.toStringZ();
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.insert_user_stmt, 3, authenticator_c, @intCast(authenticator_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind authenticator: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        if (c.SQLITE_DONE != c.sqlite3_step(self.insert_user_stmt)) {
            logErr("Step in insertOrIgnoreUser failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return;
    }

    pub fn selectUsers(self: Sqlite, alloc: std.mem.Allocator) ![]User {
        defer {
            _ = c.sqlite3_reset(self.select_users_stmt);
        }

        var user_list = std.ArrayList(User).init(alloc);
        errdefer {
            for (user_list.items) |user| {
                user.deinit();
            }
            user_list.deinit();
        }

        var step_result = c.sqlite3_step(self.select_users_stmt);
        while (step_result == c.SQLITE_ROW) : (step_result = c.sqlite3_step(self.select_users_stmt)) {
            const id = c.sqlite3_column_int64(self.select_users_stmt, 0);
            const external_id_row = c.sqlite3_column_text(self.select_users_stmt, 1);
            const external_id_len: usize = @intCast(c.sqlite3_column_bytes(self.select_users_stmt, 1));
            const login = c.sqlite3_column_text(self.select_users_stmt, 2);
            const login_len: usize = @intCast(c.sqlite3_column_bytes(self.select_users_stmt, 2));
            const authenticator_row = c.sqlite3_column_text(self.select_users_stmt, 3);
            const authenticator_row_len: usize = @intCast(c.sqlite3_column_bytes(self.select_users_stmt, 3));

            const login_buf = try alloc.alloc(u8, login_len);
            errdefer alloc.free(login_buf);
            @memcpy(login_buf, login[0..login_len]);

            const external_id_buf = try alloc.alloc(u8, external_id_len);
            errdefer alloc.free(external_id_buf);
            @memcpy(external_id_buf, external_id_row[0..external_id_len]);

            // sqlite3_column_bytes does not count the null termination in its length.
            const authenticator_enum = try Authenticator.fromStringZ(authenticator_row, authenticator_row_len + 1);

            var user = User.init(alloc);
            errdefer user.deinit();
            user.id = @as(i64, id);
            user.external_id = external_id_buf;
            user.login = login_buf;
            user.authenticator = authenticator_enum;

            try user_list.append(user);
        }

        if (c.SQLITE_DONE != step_result) {
            logErr("Step in selectUsers failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return user_list.toOwnedSlice();
    }

    pub fn selectUserByExternalId(self: Sqlite, alloc: std.mem.Allocator, external_id: []const u8, authenticator: Authenticator) !User {
        defer {
            _ = c.sqlite3_reset(self.select_user_by_external_id_stmt);
        }

        const external_id_c = try std.fmt.allocPrintZ(alloc, "{s}", .{external_id});
        defer alloc.free(external_id_c);
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.select_user_by_external_id_stmt, 1, external_id_c, @intCast(external_id_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind external_id: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        const authenticator_c = authenticator.toStringZ();
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.select_user_by_external_id_stmt, 2, authenticator_c, @intCast(authenticator_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind authenticator: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        var step_result = c.sqlite3_step(self.select_user_by_external_id_stmt);
        if (c.SQLITE_DONE == step_result) {
            return error.EmptyResult;
        }

        const id = c.sqlite3_column_int64(self.select_user_by_external_id_stmt, 0);
        const external_id_row = c.sqlite3_column_text(self.select_user_by_external_id_stmt, 1);
        const external_id_len: usize = @intCast(c.sqlite3_column_bytes(self.select_user_by_external_id_stmt, 1));
        const login = c.sqlite3_column_text(self.select_user_by_external_id_stmt, 2);
        const login_len: usize = @intCast(c.sqlite3_column_bytes(self.select_user_by_external_id_stmt, 2));
        const authenticator_row = c.sqlite3_column_text(self.select_user_by_external_id_stmt, 3);
        const authenticator_row_len: usize = @intCast(c.sqlite3_column_bytes(self.select_user_by_external_id_stmt, 3));

        const login_buf = try alloc.alloc(u8, login_len);
        errdefer alloc.free(login_buf);
        @memcpy(login_buf, login[0..login_len]);

        const external_id_buf = try alloc.alloc(u8, external_id_len);
        errdefer alloc.free(external_id_buf);
        @memcpy(external_id_buf, external_id_row[0..external_id_len]);

        // sqlite3_column_bytes does not count the null termination in its length.
        const authenticator_enum = try Authenticator.fromStringZ(authenticator_row, authenticator_row_len + 1);

        var user = User.init(alloc);
        errdefer user.deinit();
        user.id = @as(i64, id);
        user.external_id = external_id_buf;
        user.login = login_buf;
        user.authenticator = authenticator_enum;

        step_result = c.sqlite3_step(self.select_user_by_external_id_stmt);
        if (c.SQLITE_ROW == step_result) {
            return error.TooManyRows;
        } else if (c.SQLITE_DONE != step_result) {
            logErr("Step in insertOrIgnoreUser failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return user;
    }

    pub fn selectWebhook(self: Sqlite, alloc: std.mem.Allocator, user_id: i64, hook_for: HookFor) !?Webhook {
        defer {
            _ = c.sqlite3_reset(self.select_webhook_stmt);
        }

        if (c.SQLITE_OK != c.sqlite3_bind_int(self.select_webhook_stmt, 1, @intCast(user_id))) {
            logErr("Failed to bind user_id: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        const hook_for_c = hook_for.toStringZ();
        if (c.SQLITE_OK != c.sqlite3_bind_text(self.select_webhook_stmt, 2, hook_for_c, @intCast(hook_for_c.len), c.SQLITE_STATIC)) {
            logErr("Failed to bind hook_for: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.BindTextFailure;
        }

        var step_result = c.sqlite3_step(self.select_webhook_stmt);
        if (c.SQLITE_DONE == step_result) {
            return null;
        }

        const id = c.sqlite3_column_int64(self.select_webhook_stmt, 0);
        const user_id_row = c.sqlite3_column_int64(self.select_webhook_stmt, 1);
        const url = c.sqlite3_column_text(self.select_webhook_stmt, 2);
        const url_len: usize = @intCast(c.sqlite3_column_bytes(self.select_webhook_stmt, 2));
        const hook_for_row = c.sqlite3_column_text(self.select_webhook_stmt, 3);
        const hook_for_row_len: usize = @intCast(c.sqlite3_column_bytes(self.select_webhook_stmt, 3));

        const url_buf = try alloc.alloc(u8, url_len);
        errdefer alloc.free(url_buf);
        @memcpy(url_buf, url[0..url_len]);

        const hook_for_buf = try alloc.alloc(u8, hook_for_row_len);
        errdefer alloc.free(hook_for_buf);
        @memcpy(hook_for_buf, hook_for_row[0..hook_for_row_len]);

        // sqlite3_column_bytes does not count the null termination in its length.
        const hook_for_enum = try HookFor.fromStringZ(hook_for_row, hook_for_row_len + 1);

        var webhook = Webhook.init(alloc);
        errdefer webhook.deinit();
        webhook.id = @as(i64, id);
        webhook.user_id = user_id_row;
        webhook.url = url_buf;
        webhook.hook_for = hook_for_enum;

        step_result = c.sqlite3_step(self.select_webhook_stmt);
        if (c.SQLITE_ROW == step_result) {
            return error.TooManyRows;
        } else if (c.SQLITE_DONE != step_result) {
            logErr("Step in selectWebhook failed: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.StepQueryFailure;
        }

        return webhook;
    }
};

test Sqlite {
    const alloc = std.testing.allocator;
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    try Sqlite.setupTest();

    const sqlite = try Sqlite.open(Sqlite.Env.testing);
    defer sqlite.deinit();

    {
        try Sqlite.setupTest();

        const first_user = try sqlite.selectUserByExternalId(alloc, "1", Authenticator.github);
        defer first_user.deinit();
        var contact_list = try sqlite.selectContactsByUser(alloc, first_user.id.?);
        defer contact_list.deinit();
        var contact_iter = contact_list.iterator();

        try expectEqual(2, contact_iter.len);

        var first_contact = contact_iter.next().?.value_ptr.*;
        const second_contact = contact_iter.next().?.value_ptr.*;

        try expect(null != first_contact.id);
        try expectEqualStrings("Bob", first_contact.full_name);
        try expectEqual(1, first_contact.frequency_days);
        try expectEqual(86401, first_contact.due_at);

        try expect(null != second_contact.id);
        try expectEqualStrings("Timmy", second_contact.full_name);
        try expectEqual(14, second_contact.frequency_days);
        try expectEqual(120000, second_contact.due_at);

        // Test updating a contact.
        try expect(first_contact.id != null);
        const first_contact_id = first_contact.id.?;
        first_contact.frequency_days = 2;
        try sqlite.updateContact(alloc, first_contact);
        var updated_contact_list: ContactList = try sqlite.selectContactsByUser(alloc, first_user.id.?);
        defer updated_contact_list.deinit();
        const updated_first_contact = updated_contact_list.getContact(first_contact_id);
        try expect(updated_first_contact != null);
        try expectEqual(2, updated_first_contact.?.frequency_days);
    }

    {
        try Sqlite.setupTest();

        const external_id = "fake_external_id";
        const login = "fake_login";
        const authenticator = Authenticator.github;
        try sqlite.insertOrIgnoreUser(alloc, external_id, login, authenticator);

        const user = try sqlite.selectUserByExternalId(alloc, external_id, authenticator);
        defer user.deinit();
        try expect(null != user.id);
        try expectEqualStrings(external_id, user.external_id);
        try expectEqualStrings(login, user.login);
        try expectEqual(authenticator, user.authenticator);
    }

    {
        try Sqlite.setupTest();

        const user_id = 999999;
        const hook_for = HookFor.slack_notification;
        const maybe_webhook = try sqlite.selectWebhook(alloc, user_id, hook_for);
        try expect(null == maybe_webhook);
    }

    {
        try Sqlite.setupTest();

        const user_list = try sqlite.selectUsers(alloc);
        defer {
            for (user_list) |user| {
                user.deinit();
            }
            alloc.free(user_list);
        }
        try expectEqual(2, user_list.len);
    }
}

pub fn setupSqlite() !void {
    logger.info("Setting up Sqlite DB...", .{});
    try Sqlite.setup();
    logger.info("Sqlite DB done...", .{});
}

pub const Authenticator = enum {
    github,

    pub fn fromString(str: []const u8) !Authenticator {
        if (std.mem.eql(u8, "github", str)) {
            return .github;
        }

        logErr("Failed to parse str '{s}' to Authenticator", .{str});
        return error.InvalidAuthenticator;
    }

    pub fn fromStringZ(str: [*:0]const u8, str_len: usize) !Authenticator {
        return Authenticator.fromString(str[0..(str_len - 1)]);
    }

    pub fn toString(self: Authenticator) []const u8 {
        return switch (self) {
            .github => "github",
        };
    }

    pub fn toStringZ(self: Authenticator) [:0]const u8 {
        return switch (self) {
            .github => "github",
        };
    }
};

pub const User = struct {
    alloc: std.mem.Allocator,
    id: ?i64,
    external_id: []u8,
    login: []u8,
    authenticator: Authenticator,

    pub fn init(alloc: std.mem.Allocator) User {
        return .{
            .alloc = alloc,
            .id = undefined,
            .external_id = undefined,
            .login = undefined,
            .authenticator = undefined,
        };
    }

    pub fn deinit(self: User) void {
        self.alloc.free(self.external_id);
        self.alloc.free(self.login);
    }

};

pub const Contact = struct {
    alloc: std.mem.Allocator,
    id: ?i64,
    user_id: i64,
    full_name: []u8,
    frequency_days: u16,
    due_at: u32,

    pub fn init(alloc: std.mem.Allocator) Contact {
        return .{
            .alloc = alloc,
            .id = null,
            .user_id = undefined,
            .full_name = undefined,
            .frequency_days = undefined,
            .due_at = undefined,
        };
    }

    pub fn deinit(self: *Contact) void {
        self.alloc.free(self.full_name);
    }

    pub fn isDueBy(self: *Contact, time: i64) bool {
        return time >= self.due_at;
    }

    pub fn setDueAt(self: *Contact, maybe_contacted_at_seconds: ?u32) void {
        const contacted_at_seconds = if (maybe_contacted_at_seconds) |x| x else blk: {
            const now_seconds = std.time.timestamp();
            assert(now_seconds > 0);
            const contacted_at: u32 = @intCast(now_seconds);
            break :blk contacted_at;
        };

        const due_at: u32 = contacted_at_seconds + @as(u32, self.frequency_days) * std.time.s_per_day;
        self.due_at = due_at;
    }

    pub fn format(
        self: Contact,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;

        if (std.mem.eql(u8, "csv", fmt)) {
            try writer.print("{?},{d},{s},{d},{d}\n", .{
                self.id,
                self.user_id,
                self.full_name,
                self.frequency_days,
                self.due_at,
            });
        } else {
            try writer.print(
                \\Contact(
                \\  id: {?},
                \\  user_id: {d},
                \\  full_name: {s},
                \\  frequency_days: {d},
                \\  due_at: {d})
                \\
            , .{
                self.id,
                self.user_id,
                self.full_name,
                self.frequency_days,
                self.due_at,
            });
        }
    }
};

test "Contact.setDueAt" {
    const alloc = std.testing.allocator;

    var contact = Contact.init(alloc);
    defer contact.deinit();
    contact.full_name = try std.fmt.allocPrint(alloc, "{s}", .{"john doe"});
    contact.frequency_days = 30;
    contact.due_at = 1737400035;

    const contacted_at_seconds = 1737400030;
    contact.setDueAt(contacted_at_seconds);

    const expected_due_at = contacted_at_seconds + 30 * std.time.s_per_day;
    try std.testing.expectEqual(expected_due_at, contact.due_at);
}

test Contact {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    var contact = Contact.init(alloc);
    defer contact.deinit();
    contact.id = 100;
    contact.user_id = 42;
    contact.full_name = try std.fmt.allocPrint(alloc, "{s}", .{"john doe"});
    contact.frequency_days = 30;
    contact.due_at = 1737400035;

    {
        try expectEqualStrings("john doe", contact.full_name);
        try expectEqual(30, contact.frequency_days);
        try expectEqual(1737400035, contact.due_at);
    }

    {
        const formatted_contact = try std.fmt.allocPrint(alloc, "{s}", .{contact});
        defer alloc.free(formatted_contact);
        try expectEqualStrings(
            \\Contact(
            \\  id: 100,
            \\  user_id: 42,
            \\  full_name: john doe,
            \\  frequency_days: 30,
            \\  due_at: 1737400035)
            \\
        , formatted_contact);
    }

    {
        const to_csv_line = try std.fmt.allocPrint(alloc, "{csv}", .{contact});
        defer alloc.free(to_csv_line);
        try expectEqualStrings("100,42,john doe,30,1737400035\n", to_csv_line);
    }

    {
        const contacted_at_seconds = 1737400030;
        contact.setDueAt(contacted_at_seconds);
        const expected_due_at = contacted_at_seconds + 30 * std.time.s_per_day;
        try expectEqual(expected_due_at, contact.due_at);

        const to_csv_line = try std.fmt.allocPrint(alloc, "{csv}", .{contact});
        defer alloc.free(to_csv_line);
        try expectEqualStrings("100,42,john doe,30,1739992030\n", to_csv_line);
    }
}

pub const ContactList = struct {
    map: std.AutoArrayHashMap(i64, Contact),

    pub fn init(alloc: std.mem.Allocator) ContactList {
        return .{
            .map = std.AutoArrayHashMap(i64, Contact).init(alloc),
        };
    }

    pub fn deinit(self: *ContactList) void {
        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.map.deinit();
    }

    pub fn put(self: *ContactList, key: i64, contact: Contact) !void {
        try self.map.put(key, contact);
    }

    pub fn iterator(self: *ContactList) std.array_hash_map.ArrayHashMapUnmanaged(i64, Contact, std.array_hash_map.AutoContext(i64), false).Iterator {
        return self.map.iterator();
    }

    pub fn getContact(self: *ContactList, key: i64) ?Contact {
        return self.map.get(key);
    }

    pub fn getContactPtr(self: *ContactList, key: i64) ?*Contact {
        return if (self.map.getEntry(key)) |entry| entry.value_ptr else null;
    }

    pub fn format(
        self: ContactList,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;

        if (std.mem.eql(u8, "csv", fmt)) {
            var entry_iter = self.map.iterator();
            while (entry_iter.next()) |entry| {
                try writer.print("{csv}", .{entry.value_ptr.*});
            }
        } else {
            var entry_iter = self.map.iterator();
            while (entry_iter.next()) |entry| {
                try writer.print("{s}\n", .{entry.value_ptr.*});
            }
        }
    }
};

pub const HookFor = enum {
    slack_notification,

    pub fn fromString(str: []const u8) !HookFor {
        if (std.mem.eql(u8, "slack_notification", str)) {
            return .slack_notification;
        }

        logErr("Failed to parse str '{s}' to HookFor", .{str});
        return error.InvalidHookFor;
    }

    pub fn fromStringZ(str: [*:0]const u8, str_len: usize) !HookFor {
        return HookFor.fromString(str[0..(str_len - 1)]);
    }

    pub fn toString(self: HookFor) []const u8 {
        return switch (self) {
            .slack_notification => "slack_notification",
        };
    }

    pub fn toStringZ(self: HookFor) [:0]const u8 {
        return switch (self) {
            .slack_notification => "slack_notification",
        };
    }
};

pub const Webhook = struct {
    alloc: std.mem.Allocator,
    id: ?i64,
    user_id: i64,
    url: []const u8,
    hook_for: HookFor,

    pub fn init(alloc: std.mem.Allocator) Webhook {
        return .{
            .alloc = alloc,
            .id = undefined,
            .user_id = undefined,
            .url = undefined,
            .hook_for = undefined,
        };
    }

    pub fn deinit(self: Webhook) void {
        self.alloc.free(self.url);
    }
};
