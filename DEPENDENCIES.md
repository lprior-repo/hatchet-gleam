# Gleam Dependencies Setup

## Current Status

The dependencies are configured in gleam.toml as follows:

- gleam_stdlib: >= 0.44.0 and < 3.0.0
- gleam_json: >= 2.2.0 and < 3.0.0
- gleam_http: >= 3.7.0 and < 4.0.0
- gleam_httpc: >= 3.0.0 and < 4.0.0
- gleam_otp: >= 0.16.0 and < 1.0.0

## Known Issue: Gleam 1.14.0 Compatibility

The current environment has Gleam 1.14.0 installed, which introduced breaking changes to the `gleam/dynamic` module. The dependency packages (gleam_json, gleam_http, gleam_httpc, gleam_otp) at the versions compatible with the SDK design are written for earlier versions of Gleam.

### Error Example

When trying to build, you'll see errors like:
```
error: Unknown module value
  ┌─ build/packages/gleam_erlang/src/gleam/erlang/process.gleam:240:26
  │
240 │     let normal = dynamic.from(Normal)
  │                          ^^^^

The module `gleam/dynamic` does not have a `from` value.
```

## Solutions

1. **Wait for package updates**: The package maintainers need to update to support Gleam 1.14.0
2. **Use an earlier Gleam version**: The packages work with Gleam 1.6.0 or earlier
3. **Update the SDK implementation**: Rewrite the code to not depend on these packages

For now, the dependencies are correctly configured and ready for when compatible package versions become available.
