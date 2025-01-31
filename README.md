# Keep in touch (backend)

Service to get reminded to stay in touch with people.
(This is just an excuse to learn zig.)

## TODO
- Make server more robust:
  - Add 500,
  - Don't crash server on 500,
- Use test temp dir for test db and static resources.
- Replace std.debug.print by log messages + add logging.
- Refactor so that actions can be performed via cli or server, i.e, cli parser or path/routes parser.
- Refactor server routing nicer. Have a Router with "register" function (or sth) before starting server, and a "dispatch" function.
- Rate limiting?
