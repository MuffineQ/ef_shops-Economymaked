---@class ShopItem
---@field id? number internal id number, do not set
---@field name? string item name as referenced in ox_inventory
---@field category? string the category of the item in the shop (e.g. 'Snacks', 'Tools', 'Firearms', 'Ammunition', 'Drinks')
---@field license? string the license required to purchase the item
---@field jobs? table<string, number> map of group names to min grade required to access the shop
---@field metadata? table | string metadata for item

---@type table<string, table<string | number, ShopItem>>
local ITEMS = {
	normal = {
		water = { category = 'Snacks' },
		sprunk = { category = 'Snacks' },
		lighter = {},
		rolling_paper = {},
	},
	bar = {
		whiskey = {},
		vodka = {}
	},
	hardware = {
		{ name = 'lockpick', category = 'Tools' },
	},
	weapons = {
		{ name = 'WEAPON_KNIFE', category = 'Point Defense' },
		{ name = 'WEAPON_BAT', category = 'Point Defense' },
		{ name = 'WEAPON_NIGHTSTICK', category = 'Point Defense' },
		{ name = 'WEAPON_KNUCKLE', category = 'Point Defense' },
		{ name = 'WEAPON_PISTOL', license = "weapon", category = 'Firearms' },
		{ name = 'WEAPON_SNSPISTOL', license = "weapon", category = 'Firearms' },
		{ name = 'ammo-9', license = "weapon", category = 'Ammunition' },
		{ name = 'ammo-45', license = "weapon", category = 'Ammunition' },
	},
	electronics = {
		{ name = 'phone' },
		{ name = 'radio' },
	},
}

local newFormatItems = {}
for category, categoryItems in pairs(ITEMS) do
	local newCategoryItems = {}

	for item, data in pairs(categoryItems) do
		if not data.name then
			data.name = tostring(item)
		end

		newCategoryItems[#newCategoryItems + 1] = data
	end

	table.sort(newCategoryItems, function(a, b)
		return a.name < b.name
	end)

	newFormatItems[category] = newCategoryItems
end

return newFormatItems
