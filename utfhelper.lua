--[[
This code is slightly modified from https://github.com/wikimedia/mediawiki-extensions-Scribunto/blob/master/includes/engines/LuaCommon/lualib/ustring/ustring.lua

This file is released under the MIT
License:

Copyright (C) 2012 Brad Jorsch <bjorsch@wikimedia.org>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
]]

-- A private helper that splits a string into codepoints, and also collects the
-- starting position of each character and the total length in codepoints.
--
-- @param s string  utf8-encoded string to decode
-- @return table
local function utf8_explode( s )
	local ret = {
		len = 0,
		codepoints = {},
		bytepos = {},
	}

	local i = 1
	local l = string.len( s )
	local cp, b, b2, trail
	local min
	while i <= l do
		b = string.byte( s, i )
		if b < 0x80 then
			-- 1-byte code point, 00-7F
			cp = b
			trail = 0
			min = 0
		elseif b < 0xc2 then
			-- Either a non-initial code point (invalid here) or
			-- an overlong encoding for a 1-byte code point
			return nil
		elseif b < 0xe0 then
			-- 2-byte code point, C2-DF
			trail = 1
			cp = b - 0xc0
			min = 0x80
		elseif b < 0xf0 then
			-- 3-byte code point, E0-EF
			trail = 2
			cp = b - 0xe0
			min = 0x800
		elseif b < 0xf4 then
			-- 4-byte code point, F0-F3
			trail = 3
			cp = b - 0xf0
			min = 0x10000
		elseif b == 0xf4 then
			-- 4-byte code point, F4
			-- Make sure it doesn't decode to over U+10FFFF
			if string.byte( s, i + 1 ) > 0x8f then
				return nil
			end
			trail = 3
			cp = 4
			min = 0x100000
		else
			-- Code point over U+10FFFF, or invalid byte
			return nil
		end

		-- Check subsequent bytes for multibyte code points
		for j = i + 1, i + trail do
			b = string.byte( s, j )
			if not b or b < 0x80 or b > 0xbf then
				return nil
			end
			cp = cp * 0x40 + b - 0x80
		end
		if cp < min then
			-- Overlong encoding
			return nil
		end

		ret.codepoints[#ret.codepoints + 1] = cp
		ret.bytepos[#ret.bytepos + 1] = i
		ret.len = ret.len + 1
		i = i + 1 + trail
	end

	-- Two past the end (for sub with empty string)
	ret.bytepos[#ret.bytepos + 1] = l + 1
	ret.bytepos[#ret.bytepos + 1] = l + 1

	return ret
end

return utf8_explode