-- A plugin to load backup fonts
-- modified from drawwhitespaces.lua

local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"
local command = require "core.command"
local Object = require "core.object"

local utf8_explode = require "plugins.backupfonts.utfhelper"

local path = system.absolute_path -- shorthand to normalise path

local PLUGINDIR = path(EXEDIR .. "/data/plugins/backupfonts")

config.backup_fonts = {}
config.backup_fonts.enable = true
config.backup_fonts.preload_range = { lower = 0, upper = 0xFF }
config.backup_fonts.fontmap_file = path(PLUGINDIR .. "/fontmap.bin")
config.backup_fonts.fonts = {
  { path = path(EXEDIR .. "/data/fonts/monospace.ttf"), size = 13.5 },
}

--- check if file exists by stat(). This may fail, but who cares
local function file_exists(p)
  return system.get_file_info(p) ~= nil
end
  
--- convert arbitary bytes to number
local function byte_to_number(b)
  local n = {string.byte(b, 1, -1)}
  local result = 0;
  local j = 0
  for i, v in ipairs(n) do
    result = bit32.bor(result, bit32.lshift(v, j))
    j = j + 8
  end
  return result
end

--- check if os is windows based on EXEDIR
local function is_windows()
  return not not EXEDIR:find("^[a-zA-Z]:")
end

--- A font map based on a file
local Fontmap = Object:extend()

function Fontmap:new(filename, range)
  self.range = range
  self.filename = filename
  self.map_offset = 0
  self.fonts = {}
  self.map = {}
end

--- Get one font index from the file
function Fontmap:get_one(i)
  local offset = self.map_offset + i
  self.f:seek("set", offset)
  return string.byte(self.f:read(1))
end

--- Get font index in a range from the file
--- More efficient because it performs only 1 read
function Fontmap:get_range(i, j)
  self.f:seek("set", self.map_offset + i)
  local d = self.f:read(j - i)
  local bytes = {string.byte(d, 1, -1)}

  for k, v in ipairs(bytes) do
    local cp = i + k - 1
    self.map[cp] = v
  end
end

--- Open font map (maybe) can be used to reload it too
function Fontmap:open()
  self.f = io.open(self.filename, "r")
  
  local fontlen = self.f:read(1)
  self.nfonts = string.byte(fontlen)
  
  -- read font list
  -- font list never had index 0; 0 indicates that no font was available.
  for i = 1, self.nfonts, 1 do
    local namelen = self.f:read(4)
    namelen = byte_to_number(namelen)
    local name = self.f:read(namelen)
    self.fonts[name] = i
  end

  -- save offset, we might use it later
  self.map_offset = self.f:seek()

  -- read some part of map
  self:get_range(self.range.lower, self.range.upper)
end

--- Get font index from font map
function Fontmap:cp(i)
  if self.map[i] == nil then
    self.map[i] = self:get_one(i)
  end
  return self.map[i]
end


-----------------------------------------------------------
---- MAIN
-----------------------------------------------------------
local fontmap = Fontmap(config.backup_fonts.fontmap_file, config.backup_fonts.preload_range)
local fonts = {}

local user_enable = config.backup_fonts.enable -- regardless of user decision, this must be disabled during startup
config.backup_fonts.enable = false

--- check if fontmap is generated properly
local function validate_fontmap()
  local failed = 0
  for _, f in ipairs(config.backup_fonts.fonts) do
    local i = fontmap.fonts[f.path] -- font index in file
    if i == nil then
      core.log_quiet("Unable to load font %q", f.path)
      failed = failed + 1
    else
      fonts[i] = renderer.font.load(f.path, f.pixel_size or f.size * SCALE)
    end
  end
  if failed > 0 then
    core.error("Error loading some fonts. Check log for details.")
  end
end

-- A function to wait an initialise
local function wait_for_generation()
  while true do
    local stat = system.get_file_info(config.backup_fonts.fontmap_file)
    if stat and stat.size > 0xFFFF then -- since we generate up to 0xFFFF, this has to be the minimum size
      core.log("Generation complete.")
      fontmap:open()
      validate_fontmap()
      config.backup_fonts.enable = user_enable
      return
    end
    coroutine.yield()
  end
end

--- generate fontmap
local function generate_fontmap()
  local exepath = path(PLUGINDIR .. is_windows() and "mkfontmap.exe" or "mkfontmap"
  local args = { config.backup_fonts.fontmap_file }
  for i, v in ipairs(config.backup_fonts.fonts) do
    args[i + 1] = v.path
  end

  -- let's pray for this to actually execute, or else we will have an error later
  system.exec(exepath .. " " .. table.concat(args, " "))
  core.log("Generating fontmap...")

  -- register a system thread to wait for the generation
  core.add_thread(wait_for_generation)
end

if not file_exists(config.backup_fonts.fontmap_file) then
  local generate = system.show_confirm_dialog(
    "Backup fonts",
    "Fontmap not found. Generate a new one?"
  )
  if generate then generate_fontmap() else core.log("Backup fonts disabled.") end
else
  fontmap:open()
  validate_fontmap()
  config.backup_fonts.enable = user_enable
end

local draw_line_text = DocView.draw_line_text -- save the original just in case it is disabled
function DocView:draw_line_text(idx, x, y)
  if not config.backup_fonts.enable then
    draw_line_text(self, idx, x, y)
    return
  end

  -- highly inefficient, but I don't think there is any other choice
  local tx, ty = x, y + self:get_line_text_y_offset()
  for _, type, text in self.doc.highlighter:each_token(idx) do
    local color = style.syntax[type]
    local cps = utf8_explode(text)
    for i, cp in ipairs(cps.codepoints) do
      local curpos = cps.bytepos[i]
      local nextpos = (cps.bytepos[i + 1] or #text) - 1
      local chr = string.sub(text, curpos, nextpos) -- don't worry, lua string library operates on bytes
      local font = fonts[fontmap:cp(cp)] or style.code_font -- fallback font

      renderer.draw_text(font, chr, tx, ty, color)
      tx = tx + font:get_width(chr)
    end
  end
end

command.add("core.docview", {
  ["backup-fonts:toggle"]  = function() config.backup_fonts.enable = not config.backup_fonts.enable end,
  ["backup-fonts:disable"] = function() config.backup_fonts.enable = false                          end,
  ["backup fonts:enable"]  = function() config.backup_fonts.enable = true                           end,
})
