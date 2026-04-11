-- Enable snacks.image so markdown code fences like ```mermaid render
-- inline as PNGs via mmdc + kitty graphics protocol (works in Ghostty).
-- Requires: `mermaid-cli` (mmdc) and `imagemagick` — both installed via Homebrew.
return {
  "folke/snacks.nvim",
  opts = {
    image = {
      enabled = true,
      doc = {
        -- Render inline images/diagrams in markdown buffers.
        inline = true,
        float = true,
      },
    },
  },
}
