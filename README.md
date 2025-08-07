# nvim-background-autoread

Automatically reloads files when they are changed on disk without on-focus or buffer entry triggers. 


```lua
-- lazy.nvim:
{
  'bmon/nvim-background-autoread',
  opts = {
    debounce_duration = 50, -- time in ms to wait after a file is changed before reloading
  },
}
```
