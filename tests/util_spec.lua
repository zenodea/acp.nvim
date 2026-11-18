local h = require("tests.helpers")
local eq = h.eq

local util = require("acp.util")

local T = {}

function T.temp_name_returns_non_empty_string()
  local name = util.temp_name()
  eq(true, type(name) == "string", "name is a string")
  eq(true, #name > 0, "name is not empty")
end

function T.temp_name_matches_adjective_noun_pattern()
  local name = util.temp_name()
  -- "adjective-noun" — two lowercase words joined by a hyphen.
  eq(true, name:match("^%l+-%l+$") ~= nil, "name matches adjective-noun: " .. name)
end

function T.temp_name_produces_variety()
  local seen = {}
  for _ = 1, 20 do
    seen[util.temp_name()] = true
  end
  -- With 24 * 24 = 576 combinations, 20 draws should produce at least
  -- a handful of distinct names.
  local count = 0
  for _ in pairs(seen) do
    count = count + 1
  end
  eq(true, count >= 5, "temp_name produces variety: " .. count .. " unique in 20 draws")
end

function T.temp_name_slug_is_valid()
  local name = util.temp_name()
  local slug = util.slugify(name)
  -- The slug should be the name itself (already slug-safe).
  eq(name, slug, "temp name is already slug-safe")
end

return T
