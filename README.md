# Keep in touch (backend)

Service to get reminded to stay in touch with people.
(This is just an excuse to learn zig.)

## TODO
- Return contact list in json in /api/v0/contacts.
- Pass server config as options.
- Add json logger, with req id, res status, ...
- Use test temp dir for test db and static resources.
- Refactor server routing nicer. Have a Router with "register" function (or sth) before starting server, and a "dispatch" function.
- Rate limiting?
