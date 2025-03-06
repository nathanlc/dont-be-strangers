# Don't be strangers

Service to get reminded to stay in touch with people.
(This is just an excuse to learn zig.)

## TODO
- Add reminders.
- Test the removeExpired methods. App should be initiated with a "time machine" so that these can be easily tested.
- Refresh token when need be.
- Define "authenticated" endpoints (to share authentication logic).
- Tracy figure out callstack empty. No symbols, related to dsymutil macos issue?
- Tracy Flame graph?
- Pass server config as options.
- Create DB for a new user.
- Use test temp dir for test db and static resources.
- Better testing of respond methods. Pass struct containing a func to testResponse? Whhere the function does the expects?
- Refactor server routing nicer. Have a Router with "register" function (or sth) before starting server, and a "dispatch" function.
- Handle multiple requests.
- Add json logger, with req id, res status, ...
- Rate limiting?

## Run the server for development
```shell
zig build -Dgithub-client-id="${GITHUB_CLIENT_ID}" -Dgithub-client-secret="${GITHUB_CLIENT_SECRET}" run -- server
```

## Profiling
Profiling is done using Tracy.

### Build Tracy
- Clone the repo: https://github.com/wolfpld/tracy
- Build the profiler:
```shell
cmake -B profiler/build -S profiler -DCMAKE_BUILD_TYPE=Release
cmake --build profiler/build --config Release -- parallel
```
- Run the profiler:
```shell
./profiler/build/tracy-profiler
```
- Start the tracy client (dont-be-strangers server):
```shell
zig build -Dgithub-client-id="${GITHUB_CLIENT_ID}" -Dgithub-client-secret="${GITHUB_CLIENT_SECRET}" -Doptimize=ReleaseSafe -Dtracy=/path/to/tracy/ run -- server
```
