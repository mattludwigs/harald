# 1.0.*

## Breaking Changes

- [Adapter] `c::send_command/2` -> `c::cast/2`
- [HCI] remove `t::command/0` in favor of `binary()`
- [HCI] `command/2` now prepends its return with a `<<1>>`
- [Transport] remove `t::command/0` in favor of `binary()`
- [Transport] `send_command/2` -> `cast/2` (the backing `handle_call`s were
  upadted as well)
- [UART] `send_command/2` -> `cast/2` (the backing `handle_call`s were upadted
  as well)
- [UART] `cast/2` no longer prepends its `bin`s with a `<<1>>`

## Enhancements

- [Changelog] now Harald has one
- [HCI] `opcode/2` no longer guards `ogf` and `ocf` values because vendor
  specific commands may fall outside of those bounds
