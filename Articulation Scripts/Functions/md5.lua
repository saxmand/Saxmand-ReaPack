-- @version 1.0
-- @noindex

-- simple pure-lua MD5 (public-domain style implementation)
-- Source adapted for brevity; fine for small strings like emails + salt.
local export = {}
function export.md5(msg)
  local function tobytes(s) return {s:byte(1, #s)} end
  local function rol(x, n) return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF end

  local K = {}
  for i = 1, 64 do
    K[i] = math.floor(math.abs(math.sin(i)) * 2^32) & 0xFFFFFFFF
  end

  local function toLE32(n) return string.char(n & 0xFF, (n>>8) & 0xFF, (n>>16) & 0xFF, (n>>24) & 0xFF) end
  local function str2lewords(s)
    local bytes = tobytes(s)
    local words, i = {}, 1
    while i <= #bytes do
      local a = bytes[i] or 0
      local b = bytes[i+1] or 0
      local c = bytes[i+2] or 0
      local d = bytes[i+3] or 0
      words[#words+1] = a | (b<<8) | (c<<16) | (d<<24)
      i = i + 4
    end
    return words
  end

  -- padding
  local origlen = #msg
  local bitlen_low = (origlen * 8) & 0xFFFFFFFF
  local bitlen_high = math.floor(origlen * 8 / 2^32) & 0xFFFFFFFF
  msg = msg .. "\128"
  while (#msg % 64) ~= 56 do msg = msg .. "\0" end
  msg = msg .. string.char(bitlen_low & 0xFF, (bitlen_low>>8)&0xFF, (bitlen_low>>16)&0xFF, (bitlen_low>>24)&0xFF,
                           bitlen_high & 0xFF, (bitlen_high>>8)&0xFF, (bitlen_high>>16)&0xFF, (bitlen_high>>24)&0xFF)

  -- initial state
  local a0, b0, c0, d0 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476

  local S = {
    7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
    5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
    4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
    6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
  }

  local function F(x,y,z) return (x & y) | ((~x) & z) end
  local function G(x,y,z) return (x & z) | (y & (~z)) end
  local function H(x,y,z) return x ~ y ~ z end
  local function I(x,y,z) return y ~ (x | (~z)) end

  local funcs = {F, G, H, I}
  local indexfn = {}
  for i = 1, 64 do
    if i <= 16 then indexfn[i] = function(j) return j-1 end
    elseif i <= 32 then indexfn[i] = function(j) return ((5*(j-1)+1) % 16) end
    elseif i <= 48 then indexfn[i] = function(j) return ((3*(j-1)+5) % 16) end
    else indexfn[i] = function(j) return ((7*(j-1)) % 16) end end
  end

  -- process in 512-bit chunks
  local chunks = {}
  for i = 1, #msg, 64 do chunks[#chunks+1] = msg:sub(i, i+63) end
  for _, chunk in ipairs(chunks) do
    local M = str2lewords(chunk)
    local A, B, C, D = a0, b0, c0, d0
    for i = 1, 64 do
      local round = math.floor((i-1)/16) + 1
      local f = funcs[round]
      local g = indexfn[i](i)
      local X = M[g+1] or 0
      local T = (A + f(B,C,D) + K[i] + X) & 0xFFFFFFFF
      local s = S[i]
      A, D, C, B = D, C, B, (B + rol(T, s)) & 0xFFFFFFFF
    end
    a0 = (a0 + A) & 0xFFFFFFFF
    b0 = (b0 + B) & 0xFFFFFFFF
    c0 = (c0 + C) & 0xFFFFFFFF
    d0 = (d0 + D) & 0xFFFFFFFF
  end

  local digest = toLE32(a0) .. toLE32(b0) .. toLE32(c0) .. toLE32(d0)
  return (digest:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end
return export