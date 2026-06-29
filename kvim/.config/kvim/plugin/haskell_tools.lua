vim.g.haskell_tools = {
  hls = {
    default_settings = {
      haskell = {
        plugin = {
          inlayHints = {
            globalOn = true,
            config = {
              typeHints = true,
              parameterNames = true,
            }
          }
        }
      }
    }
  }
}
