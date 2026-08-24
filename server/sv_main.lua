lib.versionCheck('jellyton69/ef-shops')
if not lib.checkDependency('qbx_core', '1.6.0') then error() end
if not lib.checkDependency('ox_lib', '3.0.0') then error() end
if not lib.checkDependency('ox_inventory', '2.20.0') then error() end

local TriggerEventHooks = require '@qbx_core.modules.hooks'

local ox_inventory = exports.ox_inventory
local ITEMS = ox_inventory:Items()

local PRODUCTS = require 'config.shop_items' ---@type table<string, table<string, ShopItem>>
local LOCATIONS = require 'config.locations' ---@type type<string, ShopLocation>

local function getBusinessForShop(shopType, location)
	local shop = ShopData[shopType] and ShopData[shopType][location]
	if not shop or not shop.coords then return nil end

	local businesses = exports.economyreworked:GetBusinesses(shopType)
	for _, business in ipairs(businesses) do
		local coords = business.coords
		if coords then
			local x = shop.coords.x - coords.x
			local y = shop.coords.y - coords.y
			local z = shop.coords.z - coords.z
			if (x * x) + (y * y) + (z * z) < 25.0 then
				return business
			end
		end
	end
end

local function getServicesByName(shopType)
	local economyConfig = exports.economyreworked:GetConfig()
	local services = economyConfig and economyConfig.Services and economyConfig.Services[shopType] or {}
	local servicesByName = {}

	for _, service in ipairs(services) do
		servicesByName[service.name] = service
	end

	return servicesByName, economyConfig
end

local function isNpcBusiness(business)
	local owner = business and business.owner
	return owner == nil or owner == false or owner == '' or owner == 'NULL'
end

local function getEconomyInventory(shopType, location)
	local business = getBusinessForShop(shopType, location)
	local shop = ShopData[shopType] and ShopData[shopType][location]
	if not business or not shop then return nil end

	local services, economyConfig = getServicesByName(shopType)
	local inventory = {}
	local isNpcShop = isNpcBusiness(business)

	for _, shopItem in ipairs(shop.inventory) do
		local service = services[shopItem.name]
		local product = business.products and business.products[shopItem.name]
		if service and (isNpcShop or (product and product.enabled)) then
			local item = lib.table.deepclone(shopItem)
			local stockCost = tonumber(service.stockCost) or 1
			item.price = isNpcShop and math.floor(service.price * economyConfig.NPCMargin) or product.price
			item.count = isNpcShop and 50 or math.floor((business.stock or 0) / stockCost)
			item.stockCost = stockCost
			if not isNpcShop then
				item.sharedStock = business.stock
			end
			inventory[#inventory + 1] = item
		end
	end

	return inventory, business, services
end

ShopData = {}

---@class ShopData
---@field name string
---@field location string
---@field inventory OxItem[]
---@field groups table

---@param shopType string
---@param shopData table
local function registerShop(shopType, shopData)
	ShopData[shopType] = {}

	if shopData.coords then
		for locationId, locationData in pairs(shopData.coords) do
			local shop = {
				name = shopData.name,
				location = locationId,
				inventory = lib.table.deepclone(shopData.inventory),
				groups = shopData.groups,
				coords = locationData
			}

			ShopData[shopType][locationId] = shop
		end
	else
		local shop = {
			name = shopData.name,
			inventory = lib.table.deepclone(shopData.inventory),
			groups = shopData.groups
		}

		ShopData[shopType][1] = shop
	end
end

lib.callback.register("EF-Shops:Server:OpenShop", function(source, shop_type, location)
	local inventory = getEconomyInventory(shop_type, location)
	return inventory
end)

local mapBySubfield = function(tbl, subfield)
	local mapped = {}
	for i = 1, #tbl do
		local item = tbl[i]
		mapped[item[subfield]] = item
	end
	return mapped
end

lib.callback.register("EF-Shops:Server:PurchaseItems", function(source, purchaseData)
	if not purchaseData then
		lib.print.warn(GetPlayerName(source) .. " may be attempting to exploit EF-Shops:Server:PurchaseItems.")
		return false
	end

	if not purchaseData.shop then
		lib.print.warn(GetPlayerName(source) .. " may be attempting to exploit EF-Shops:Server:PurchaseItems.")
		lib.print.warn(purchaseData)
		return false
	end

	local player = exports.qbx_core:GetPlayer(source)
	local shop = ShopData[purchaseData.shop.id] and ShopData[purchaseData.shop.id][purchaseData.shop.location]
	local shopType = purchaseData.shop.id

	if not shop then
		lib.print.error("Invalid shop: " .. purchaseData.shop.id .. " called by: " .. GetPlayerName(source))
		return false
	end

	local shopData = LOCATIONS[purchaseData.shop.id]

	if shopData.jobs then
		if not shopData.jobs[player.PlayerData.job.name] then
			lib.print.error("Invalid job: " .. player.PlayerData.job.name .. " for shop: " .. purchaseData.shop.id .. " called by: " .. GetPlayerName(source))
			return
		end

		if shopData.jobs[player.PlayerData.job.name] > player.PlayerData.job.grade.level then
			lib.print.error("Invalid job grade: " .. player.PlayerData.job.grade.level .. " for shop: " .. purchaseData.shop.id .. " called by: " .. GetPlayerName(source))
			return
		end
	end

	local currency = purchaseData.currency
	if currency ~= "cash" and currency ~= "bank" then
		lib.print.warn("Invalid payment account called by: " .. GetPlayerName(source))
		return false
	end

	local economyInventory, business, services = getEconomyInventory(shopType, purchaseData.shop.location)
	if not economyInventory or not business then
		lib.print.error("No economy business found for shop: " .. shopType .. " called by: " .. GetPlayerName(source))
		return false
	end

	local mappedCartItems = mapBySubfield(purchaseData.items, "id")
	local validCartItems = {} ---@type OxItem[]

	local totalPrice = 0
	local totalStockCost = 0
	for i = 1, #economyInventory do
		local shopItem = economyInventory[i]
		local itemData = ITEMS[shopItem.name]
		local mappedCartItem = mappedCartItems[shopItem.id]

		if mappedCartItem then
			if shopItem.license and player.PlayerData.metadata.licences[shopItem.license] ~= true then
				TriggerClientEvent('ox_lib:notify', source, { title = "You do not have the license to purchase this item (" .. shopItem.license .. ").", type = "error" })
				goto continue
			end

			if not exports.ox_inventory:CanCarryItem(source, shopItem.name, mappedCartItem.quantity) then
				TriggerClientEvent('ox_lib:notify', source, { title = "You cannot carry the requested quantity of " .. itemData.label .. "s.", type = "error" })
				goto continue
			end

			if shopItem.count and (mappedCartItem.quantity > shopItem.count) then
				TriggerClientEvent('ox_lib:notify', source, { title = "The requested amount of " .. itemData.label .. " is no longer in stock.", type = "error" })
				goto continue
			end

			if shopItem.jobs then
				if not shopItem.jobs[player.PlayerData.job.name] then
					TriggerClientEvent('ox_lib:notify', source, { title = "You do not have the required job to purchase " .. itemData.label .. ".", type = "error" })
					goto continue
				end
				if shopItem.jobs[player.PlayerData.job.name] > player.PlayerData.job.grade.level then
					TriggerClientEvent('ox_lib:notify', source, { title = "You do not have the required grade to purchase " .. itemData.label .. ".", type = "error" })
					goto continue
				end
			end

			local newIndex = #validCartItems + 1
			validCartItems[newIndex] = mappedCartItem
			validCartItems[newIndex].inventoryIndex = i

			totalPrice = totalPrice + (shopItem.price * mappedCartItem.quantity)
			totalStockCost = totalStockCost + ((services[shopItem.name].stockCost or 1) * mappedCartItem.quantity)
		end

		:: continue ::
	end

	if #validCartItems == 0 then
		return false
	end

	for i = 1, #validCartItems do
		local item = validCartItems[i]
		local itemData = ITEMS[item.name]
		local productData = PRODUCTS[shopData.shopItems][item.id]

		if not itemData or not productData then
			lib.print.error("Invalid product " .. item.name .. " in shop: " .. shopType)
			return false
		end

		if TriggerEventHooks('buyItem', {
			source = source,
			shopId = purchaseData.shop.id,
			shopLocation = purchaseData.shop.location,
			item = itemData,
			product = productData,
			currency = currency,
		}) == false then
			return false
		end
	end

	if not exports.economyreworked:PerformService(business.id, totalPrice, totalStockCost, currency, source) then
		return false
	end

	local itemStrings = {}
	for i = 1, #validCartItems do
		local item = validCartItems[i]
		local itemData = ITEMS[item.name]
		itemStrings[#itemStrings + 1] = item.quantity .. "x " .. itemData.label
	end
	local purchaseReason = table.concat(itemStrings, "; ")

	for i = 1, #validCartItems do
		local item = validCartItems[i]
		local itemData = ITEMS[item.name]
		local productData = PRODUCTS[shopData.shopItems][item.id]

		if not itemData then
			lib.print.error("Invalid item: " .. item.name .. " in shop: " .. shopType)
			goto continue
		end

		if not productData then
			lib.print.error("Invalid product: " .. item.name .. " in shop: " .. shopType)
			goto continue
		end

		local success, response = ox_inventory:AddItem(source, item.name, item.quantity, productData.metadata)
		if success then
			TriggerEventHooks('itemPurchased', {
				source = source,
				shopId = purchaseData.shop.id,
				shopLocation = purchaseData.shop.location,
				items = response,
				product = shop.inventory[item.inventoryIndex],
				currency = currency,
			})
		else
			lib.print.error("Failed adding " .. item.name .. " after economy transaction: " .. purchaseReason)
		end

		:: continue ::
	end

	return true
end)

AddEventHandler('onResourceStart', function(resource)
	if GetCurrentResourceName() ~= resource and "ox_inventory" ~= resource then return end

	for productType, productData in pairs(PRODUCTS) do
		for _, item in pairs(productData) do
			if not ITEMS[(string.find(item.name, "weapon_") and (item.name):upper()) or item.name] then
				lib.print.error("Invalid Item: ", item, "in product table:", productType, "^7")
				productData[item] = nil
			end
		end
	end

	for shopID, shopData in pairs(LOCATIONS) do
		if not shopData.shopItems or not PRODUCTS[shopData.shopItems] then
			lib.print.error("A valid product ID (" .. shopData.shopItems .. ") for [" .. shopID .. "] was not found.")
			goto continue
		end

		local shopProducts = {}
		for item, data in pairs(PRODUCTS[shopData.shopItems]) do
			shopProducts[#shopProducts + 1] = {
				id = tonumber(item),
				name = data.name,
				license = data.license,
				metadata = data.metadata,
				jobs = data.jobs
			}
		end

		table.sort(shopProducts, function(a, b)
			return a.name < b.name
		end)

		registerShop(shopID, {
			name = shopData.Label,
			inventory = shopProducts,
			groups = shopData.groups,
			coords = shopData.coords
		})

		::continue::
	end
end)
