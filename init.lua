-- A plugin to load fallback
-- modified from drawwhitespaces.lua

local core = require "core"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"
local command = require "core.command"
local Object = require "core.object"

local utf8_explode = require "plugins.fallbackfonts.utfhelper"
local path = system.absolute_path -- shorthand to normalise path

local PLUGINDIR = path(EXEDIR .. "/data/plugins/fallbackfonts")
local MAX_CODEPOINT = 0xFFFF

---------------------------------------------------------------
---- Configuraation
---------------------------------------------------------------
config.fallback_fonts = {}
config.fallback_fonts.enable = false
config.fallback_fonts.preload_range = { lower = 0, upper = 0xFF }
config.fallback_fonts.fontmap_file = path(PLUGINDIR .. "/fontmap.bin")
config.fallback_fonts.fonts = {
  { path = path(EXEDIR .. "/data/fonts/monospace.ttf"), size = 13.5 },
}

---------------------------------------------------------------
---- Utilities and classes
---------------------------------------------------------------
--- check if file exists by stat(). This may fail, but who cares
local function file_exists(p)
  return system.get_file_info(p) ~= nil
end

--- convert arbitary bytes to number
local function byte_to_number(b)
  local n = {string.byte(b, 1, -1)}
  local result = 0;
  local j = 0
  for _, v in ipairs(n) do
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
local fontmap, fonts

--- check if fontmap is generated properly
local function validate_fontmap()
  local failed = 0

  for _, f in ipairs(config.fallback_fonts.fonts) do
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

--- generate fontmap
local function generate_fontmap()

  local function wait()
    while true do
      coroutine.yield()
      local stat = system.get_file_info(config.fallback_fonts.fontmap_file)
      if stat and stat.size > MAX_CODEPOINT then
        core.log("Fontmap generated.")
        fontmap:open()
        return validate_fontmap()
      end
    end
  end

  local EXEPATH = path(PLUGINDIR .. (is_windows() and "/mkfontmap.exe" or "/mkfontmap"))
  local args = { config.fallback_fonts.fontmap_file }
  for i, v in ipairs(config.fallback_fonts.fonts) do
    args[i + 1] = v.path
  end

  -- let's pray for this to actually execute, or else we will have an error later
  system.exec(EXEPATH .. " " .. table.concat(args, " "))
  core.log("Generating fontmap...")

  -- register a system thread to wait for the generation
  core.add_thread(wait)
end

-- initialization function. Must be called after setting configs in init.lua
local function initialize()
  fontmap = Fontmap(config.fallback_fonts.fontmap_file, config.fallback_fonts.preload_range)
  fonts = {}

  if not file_exists(config.fallback_fonts.fontmap_file) then
    local generate = system.show_confirm_dialog(
      "Fallback fonts",
      "Fontmap not found. Generate a new one?"
    )
    if generate then
      generate_fontmap()
    else
      config.fallback_fonts.enable = false
      core.log("Backup fonts disabled.")
    end
  else
    fontmap:open()
    validate_fontmap()
  end
end

local function delete_fontmap()
  local result, err
  if system.show_confirm_dialog("Fallback fonts", "Do you want to delete the fontmap?") then
    if io.type(fontmap.f) == "file" then fontmap.f:close() end
    result, err = os.remove(config.fallback_fonts.fontmap_file)
    if result then
      core.log("Fontmap deleted.")
    else
      core.error("Unable to delete fontmap: %s", err)
    end
  else
    result, err = nil, "User cancelled operation."
    core.log("User cancelled operation.")
  end
  return result, err
end

local function regenerate_fontmap()
  local result = delete_fontmap()
  if result then generate_fontmap() end
end

-----------------------------------------------------------
---- EXTENSIONS
-----------------------------------------------------------
local get_col_x_offset = DocView.get_col_x_offset
function DocView:get_col_x_offset(line, col)
  if not config.fallback_fonts.enable then
    return get_col_x_offset(self, line, col)
  end

  local result = 0
  if self.linexbuf == nil then self.linexbuf = {} end
  if self.linexbuf[line] == nil then
    -- generate it on the fly; less optimal but will work
    local text = self.doc.lines[line]
    if not text then return 0 end

    self.linexbuf[line] = {}
    local cps = utf8_explode(text)
    for i, cp in ipairs(cps.codepoints) do
      if i == col then break end
      local curpos = cps.bytepos[i]
      local nextpos = (cps.bytepos[i + 1] or #text) - 1
      local chr = string.sub(text, curpos, nextpos)
      local font = fonts[fontmap:cp(cp)] or style.code_font
      local fw = font:get_width(chr)
      result = result + fw
      self.linexbuf[line][i] = fw
    end
  else
    local xoffset = self.linexbuf[line]
    for i, v in ipairs(xoffset) do
      if i == col then break end
      result = result + v
    end
  end
  return result
end

local draw_line_text = DocView.draw_line_text -- save the original just in case it is disabled
function DocView:draw_line_text(idx, x, y)
  if not config.fallback_fonts.enable then
    draw_line_text(self, idx, x, y)
    return
  end

  -- highly inefficient, but I don't think there is any other choice
  if self.linexbuf == nil then self.linexbuf = {} end
  if self.linexbuf[idx] == nil then self.linexbuf[idx] = {} end
  local tx, ty = x, y + self:get_line_text_y_offset()
  local col = 1
  for _, type, text in self.doc.highlighter:each_token(idx) do
    local color = style.syntax[type]
    local cps = utf8_explode(text)
    for i, cp in ipairs(cps.codepoints) do
      local curpos = cps.bytepos[i]
      local nextpos = (cps.bytepos[i + 1] or #text) - 1
      local chr = string.sub(text, curpos, nextpos) -- don't worry, lua string library operates on bytes
      local font = fonts[fontmap:cp(cp)] or style.code_font -- fallback font

      renderer.draw_text(font, chr, tx, ty, color)
      local fw = font:get_width(chr)
      tx = tx + fw
      self.linexbuf[idx][col] = fw
      col = col + 1
    end
  end
end


command.add("core.docview", {
  ["fallback-fonts:toggle"]         = function() config.fallback_fonts.enable = not config.fallback_fonts.enable end,
  ["fallback-fonts:enable"]         = function() config.fallback_fonts.enable = true                             end,
  ["fallback-fonts:disable"]        = function() config.fallback_fonts.enable = false                            end,
})
command.add(nil, {
  ["fallback-fonts:delete-fontmap"]     = delete_fontmap,
  ["fallback-fonts:regenerate-fontmap"] = regenerate_fontmap,
})

return initialize