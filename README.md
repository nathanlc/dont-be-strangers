# Don't be strangers

Service to get reminded to stay in touch with people.
(This is just an excuse to learn zig.)

## TODO
- Do a 0.1.0 release.
- Add timestamps to logs.
- Refresh token when need be.
- Test the removeExpired methods. App should be initiated with a "time machine" so that these can be easily tested.
- Make web app so it can be a "mobile" app.
- Define "authenticated" endpoints (to share authentication logic), middleware?.
- Tracy figure out callstack empty. No symbols, related to dsymutil macos issue?
- Tracy Flame graph?
- Pass server config as options (port, ...).
- Use test temp dir for test db and static resources.
- Better testing of respond methods. Pass struct containing a func to testResponse? Whhere the function does the expects?
- Refactor server routing nicer. Have a Router with "register" function (or sth) before starting server, and a "dispatch" function.
- Improve request body parsing
  - Add error messages to responses.
  - Handle form url encoding, unicode code points.
- Handle multiple requests.
- Add templating system.
- Ziggify sqlite.
- Rate limiting?

## External dependencies
- Github application setup for OAuth authentication via github: https://github.com/settings/apps/dont-be-strangers

## Build a "release" bin
For the current platform:
```
zig build -Doptimize=ReleaseSafe
```
For a different platform (e.g. arm-linux):
```
zig build -Doptimize=ReleaseSafe -Dtarget=arm-linux
```

## Development
### Run build with file system watching
The env variables GITHUB_CLIENT_ID and GITHUB_SECRET must be set.
```
zig build -Dno-bin -fincremental --watch
```

### Run tests automatically
```shell
ls src/* | entr -cc -s 'zig build test --summary all'
# OR
ls src/* | entr -cc -s 'zig test -I lib/c/sqlite -lsqlite3 src/test.zig'
```

### Run the server
The env variables GITHUB_CLIENT_ID and GITHUB_SECRET must be set.
```shell
zig build run -- server
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

## Old code reference
At the time of the branch [old_reference](https://github.com/nathanlc/dont-be-strangers/tree/old_reference), sqlite was introduced instead of using CSV. Some code that wasn't needed but kept to have Zig references was cleaned up. Keeping this comment here to easily check old implementation.
