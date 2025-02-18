# Don't be strangers

Service to get reminded to stay in touch with people.
(This is just an excuse to learn zig.)

## TODO
- Pass server config as options.
- Create DB for a new user.
- Use test temp dir for test db and static resources.
- Better testing of respond methods. Pass struct containing a func to testResponse? Whhere the function does the expects?
- Refactor server routing nicer. Have a Router with "register" function (or sth) before starting server, and a "dispatch" function.
- Handle multiple requests.
- Add json logger, with req id, res status, ...
- Rate limiting?
