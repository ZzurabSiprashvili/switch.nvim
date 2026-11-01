# switch.nvim

Cycle through groups of keywords without leaving Neovim.

Each entry in `keywords` is a group. When the switch mapping is pressed, every
matching keyword in the current scope is replaced with the **next** keyword in
its own group. The last keyword in a group wraps around to the first one.

```lua
keywords = {
  { "true", "false" },
  { "yes", "no" },
  { "on", "off" },
}
```

For example, with the group `{ "true", "false" }`:

```text
true false  ->  false true
```

The recommended mapping is `<leader><TAB>`, which is the default.

## Requirements

- Neovim 0.9 or newer

## Installation

### lazy.nvim

```lua
{
  "ZzurabSiprashvili/switch.nvim",
  config = function()
    require("switch").setup({
      keywords = {
        { "true", "false" },
        { "yes", "no" },
        { "on", "off" },
      },
    })
  end,
}
```

### packer.nvim

```lua
use({
  "ZzurabSiprashvili/switch.nvim",
  config = function()
    require("switch").setup({
      keywords = {
        { "true", "false" },
        { "yes", "no" },
        { "on", "off" },
      },
    })
  end,
})
```

### Manual

Clone the repository somewhere on your `runtimepath` and call `setup()`:

```lua
vim.opt.runtimepath:append("/path/to/switch.nvim")
require("switch").setup({
  keywords = {
    { "true", "false" },
    { "yes", "no" },
  },
})
```

## Configuration

```lua
require("switch").setup({
  -- Groups of keywords. Each group is cycled independently.
  keywords = {
    { "true", "false" },
    { "left", "right" },
    { "up", "down" },
  },

  -- Key mapping. Set to false to disable it.
  keymap = "<leader><TAB>",

  -- Where to look for keywords:
  --   "line"   - all keywords on the current line (default)
  --   "buffer" - all keywords in the current buffer
  --   "cursor" - only the keyword under the cursor
  scope = "line",

  -- Match keywords regardless of case.
  ignore_case = false,

  -- When ignore_case is true, keep the casing of the matched text:
  -- `True` -> `False`, `TRUE` -> `FALSE`, `true` -> `false`.
  preserve_case = false,

  -- Show a message when nothing was replaced.
  notify = false,

  -- Create the `:Switch` user command.
  command = true,
})
```

### Scope examples

```lua
-- Replace everything on the current line.
require("switch").switch({ scope = "line" })

-- Replace every keyword in the buffer.
require("switch").switch({ scope = "buffer" })

-- Replace only the keyword under the cursor.
require("switch").switch({ scope = "cursor" })
```

The `:Switch` command accepts an optional scope override:

```vim
:Switch
:Switch buffer
:Switch cursor
```

## Technical examples

### JavaScript / TypeScript

Switch between absence values and booleans:

```lua
require("switch").setup({
  keywords = {
    { "undefined", "null" },
    { "true", "false" },
  },
  keymap = "<leader><TAB>",
})
```

```ts
const value = undefined;
// <leader><TAB>
const value = null;
```

Because matches are whole-word and per group, `undefined`/`null` and
`true`/`false` can be switched independently on the same line.

### Go types

Cycle through the sized integer and floating-point types:

```lua
require("switch").setup({
  keywords = {
    { "int", "int8", "int16", "int32", "int64" },
    { "uint", "uint8", "uint16", "uint32", "uint64" },
    { "float32", "float64" },
    { "complex64", "complex128" },
  },
  keymap = "<leader><TAB>",
})
```

```go
var count int
// <leader><TAB>
var count int8
// <leader><TAB>
var count int16
```

The groups wrap around:

```text
int -> int8 -> int16 -> int32 -> int64 -> int
uint -> uint8 -> uint16 -> uint32 -> uint64 -> uint
float32 -> float64 -> float32
complex64 -> complex128 -> complex64
```

These are text switches, not semantic type conversions. The plugin only
replaces the type name; it does not cast values or rewrite conversions.

## Behavior details

- Replacements happen in a single pass. Matches are found against the original
  text, so a replacement is never processed again.
- Longer keywords are matched first. With the groups
  `{ { "is", "was" }, { "is not", "wasn't" } }`, the text `is not` becomes
  `wasn't` instead of being handled as `is` followed by a separate `not`.
- Keywords only match whole words when they start or end with a word character.
  `true` does not match inside `untrue`, while keywords made of symbols such as
  `++` and `--` work as expected.
- A group with one keyword replaces it with itself (there is no other value to
  cycle to).
- Duplicate keywords across groups are rejected, because cycling would be
  ambiguous.

## API

```lua
local switch = require("switch")

switch.setup(opts)              -- configure the plugin
switch.switch(opts)             -- run a switch manually, returns match count
switch.get_config()             -- get a copy of the current configuration
switch.is_setup()               -- whether setup() has been called
```

## Tests

The test suite uses plain Neovim and has no external dependencies:

```sh
nvim --headless --clean -l tests/run.lua
```

## License

MIT
