const std = @import("std");

const logger = std.log.scoped(.http);

fn eqlU8(str1: []const u8, str2: []const u8) bool {
    return std.mem.eql(u8, str1, str2);
}

pub const Mime = enum {
    text_html,
    text_javascript,
    text_css,
    text_plain,
    application_json,
    application_x_www_form_url_encoded,
    image_x_icon,
    image_svg,
    image_png,

    pub fn fromString(file_name: []const u8) !Mime {
        var iter = std.mem.splitBackwardsScalar(u8, file_name, '.');
        const extension = iter.first();

        if (eqlU8("html", extension)) {
            return Mime.text_html;
        } else if (eqlU8("js", extension)) {
            return Mime.text_javascript;
        } else if (eqlU8("css", extension)) {
            return Mime.text_css;
        } else if (eqlU8("txt", extension)) {
            return Mime.text_plain;
        } else if (eqlU8("webmanifest", extension) or (eqlU8("json", extension))) {
            return Mime.application_json;
        } else if (eqlU8("ico", extension)) {
            return Mime.image_x_icon;
        } else if (eqlU8("svg", extension)) {
            return Mime.image_svg;
        } else if (eqlU8("png", extension)) {
            return Mime.image_png;
        }

        logger.warn("Unexpected extension: {s}\n  for file_name: {s}\nReturning text/plain", .{ extension, file_name });
        return error.MimeNotFound;
    }

    pub fn toString(self: Mime) []const u8 {
        return switch (self) {
            Mime.text_html => "text/html",
            Mime.text_javascript => "text/javascript",
            Mime.text_css => "text/css",
            Mime.text_plain => "text/plain",
            Mime.application_json => "application/json",
            Mime.application_x_www_form_url_encoded => "application/x-www-form-urlencoded",
            Mime.image_x_icon => "image/x-icon",
            Mime.image_svg => "image/svg",
            Mime.image_png => "image/png",
        };
    }
};

