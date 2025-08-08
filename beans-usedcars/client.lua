local QBCore = exports['qb-core']:GetCoreObject()
local insideSellZone = false

-- Returns a reduced resale price based on mileage tiers
function CalculateUsedVehiclePrice(basePrice, mileage)
    if not Config.MileageTiers then return math.floor(basePrice * 0.8) end
    for _, tier in ipairs(Config.MileageTiers) do
        if mileage >= tier.min and mileage <= tier.max then
            local reduction = basePrice * (tier.penaltyPercent / 100)
            return math.floor((basePrice * 0.8) - reduction)
        end
    end
    return math.floor(basePrice * 0.8)
end

local function ShowSellPrompt()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end

    local modelHash = GetEntityModel(veh)
    local modelName = nil

    for name, data in pairs(QBCore.Shared.Vehicles) do
        if joaat(data.model) == modelHash then
            modelName = data.model:lower()
            break
        end
    end

    if not modelName then
        lib.notify({ title = 'Error', description = 'Vehicle model not recognized.', type = 'error' })
        return
    end

    local price = GetVehiclePriceFromShared(modelName)
    if price <= 0 then
        lib.notify({ title = 'Error', description = 'Vehicle not sellable.', type = 'error' })
        return
    end

    local props = QBCore.Functions.GetVehicleProperties(veh)
    local mileage = Entity(veh).state.mileage or props.mileage or 0
    local payout = CalculateUsedVehiclePrice(price, mileage)

    lib.registerContext({
        id = 'usedcar_sell_menu',
        title = 'Sell Vehicle to Dealership',
        options = {
            {
                title = ('Sell %s for $%s'):format(GetDisplayNameFromVehicleModel(modelHash), payout),
                icon = 'dollar-sign',
                onSelect = function()
                    print("📤 Sending SellVehicle trigger:", GetVehicleNumberPlateText(veh), modelName)
TriggerServerEvent('beans-usedcars:server:SellVehicle', GetVehicleNumberPlateText(veh), modelName, props)
                    TaskLeaveVehicle(ped, veh, 0)
                    Wait(1500)
                    SetEntityAsMissionEntity(veh, true, true)
                    DeleteVehicle(veh)
                end
            }
        }
    })

    lib.showContext('usedcar_sell_menu')
end

-- Dealership Sell Zone
CreateThread(function()
    lib.zones.box({
        coords = Config.SellZone.coords,
        size = Config.SellZone.size,
        rotation = Config.SellZone.rotation,
        debug = false,
        inside = function()
            if not insideSellZone and IsPedInAnyVehicle(PlayerPedId(), false) then
                insideSellZone = true
                lib.showTextUI('[E] Sell Vehicle')
            end

            if insideSellZone and IsControlJustPressed(0, 38) then
                ShowSellPrompt()
            end
        end,
        onExit = function()
            if insideSellZone then
                insideSellZone = false
                lib.hideTextUI()
            end
        end
    })
end)

-- When server tells us to spawn display vehicle
RegisterNetEvent("beans-usedcars:client:SpawnVehicleForSale", function(data)
    local coords = data.coords
    local model = data.model
    local plate = data.plate
    local mods = {}

    lib.requestModel(model)

    local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, false, true)
    while not DoesEntityExist(vehicle) do Wait(10) end

    SetVehicleNumberPlateText(vehicle, plate)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)

    -- Decode and apply vehicle mods if available
    if data.mods and type(data.mods) == "string" then
        local success, decoded = pcall(json.decode, data.mods)
        if success and type(decoded) == "table" then
            mods = decoded
            lib.setVehicleProperties(vehicle, mods)
        else
            print("❌ Failed to decode vehicle mods for plate:", plate)
        end
    else
        print("❌ No mods provided for vehicle spawn:", plate)
    end

    exports.ox_target:addLocalEntity(vehicle, {
        {
            icon = "fa-solid fa-dollar-sign",
            label = ("Buy Vehicle ($%s)"):format(data.price),
            onSelect = function()
                print("🛒 Buy Vehicle selected for plate:", plate)

                lib.callback('beans-usedcars:server:GetUsedVehicleInfo', false, function(info)
                    if not info then
                        return lib.notify({ title = 'Error', description = 'Vehicle info not found.', type = 'error' })
                    end

                    print("🔧 Upgrade info from server:", json.encode(info))

                    -- Parse/sanitize
                    local engine       = tonumber(info.engine or -1)
                    local turbo        = info.turbo == true
                    local brakes       = tonumber(info.brakes or -1)
                    local transmission = tonumber(info.transmission or -1)
                    local suspension   = tonumber(info.suspension or -1)
                    local mileage      = tonumber(info.mileage or 0)
                    local price        = tonumber(info.price or 0)
                    local color = (info.color1 and #info.color1 == 3)
                        and ("R:%s G:%s B:%s"):format(info.color1[1], info.color1[2], info.color1[3])
                        or "Unknown"

                    local upgrades = {
                        {
                            title = "Engine Upgrade",
                            description = (engine > 0 and ("Level %d"):format(engine)) or "None",
                            icon = "wrench",
                            disabled = true,
                        },
                        {
                            title = "Turbocharger",
                            description = turbo and "Installed" or "None",
                            icon = "wind",
                            disabled = true,
                        },
                        {
                            title = "Brakes",
                            description = (brakes > 0 and ("Level %d"):format(brakes)) or "None",
                            icon = "car-burst",
                            disabled = true,
                        },
                        {
                            title = "Transmission",
                            description = (transmission > 0 and ("Level %d"):format(transmission)) or "None",
                            icon = "gear",
                            disabled = true,
                        },
                        {
                            title = "Suspension",
                            description = (suspension > 0 and ("Level %d"):format(suspension)) or "None",
                            icon = "arrows-down-to-line",
                            disabled = true,
                        },
                        {
                            title = "Mileage",
                            description = ("%0.1f miles"):format(mileage),
                            icon = "road",
                            disabled = true,
                        },
                        {
                            title = "Color",
                            description = color,
                            icon = "palette",
                            disabled = true,
                        },
                        {
                            title = ("Confirm Purchase for $%s"):format(price),
                            icon = "dollar-sign",
 onSelect = function()
    lib.callback('beans-usedcars:server:BuyVehicle', false, function(result)
        if not result or not result.success then
            return lib.notify({
                title = 'Purchase Failed',
                description = 'Not enough money or an error occurred.',
                type = 'error'
            })
        end

        lib.notify({
            title = 'Purchase Successful',
            description = 'Your vehicle is ready!',
            type = 'success'
        })

        -- 🧽 Cleanup: delete display vehicle
        local displayVeh = GetClosestVehicle(coords.x, coords.y, coords.z, 3.0, 0, 70)
        if displayVeh ~= 0 and DoesEntityExist(displayVeh) then
            DeleteEntity(displayVeh)
        end

        -- 🚗 Spawn purchased vehicle at delivery coords
        local delivery = Config.DeliverySpawn
        lib.requestModel(result.model)

        local veh = CreateVehicle(result.model, delivery.x, delivery.y, delivery.z, delivery.w, true, false)
        while not DoesEntityExist(veh) do Wait(10) end

        SetVehicleNumberPlateText(veh, result.plate)
        SetPedIntoVehicle(PlayerPedId(), veh, -1)

        if result.mods and type(result.mods) == "string" then
            local ok, mods = pcall(json.decode, result.mods)
            if ok and type(mods) == "table" then
                lib.setVehicleProperties(veh, mods)
            end
        end

        -- 🔑 Give keys (you can replace this with your own key system)
        TriggerEvent("vehiclekeys:client:SetOwner", result.plate)

        -- 🔁 Attempt to refill the lot
        TriggerServerEvent("beans-usedcars:server:TryRefillShowroom")

        -- ✅ Close context
        lib.hideContext()
    end, info.plate)
end

                        }
                    }

                    lib.registerContext({
                        id = 'usedcar_preview_' .. info.plate,
                        title = 'Used Vehicle Preview',
                        options = upgrades
                    })

                    lib.showContext('usedcar_preview_' .. info.plate)
                end, data.plate)
            end
        }
    })
end)






-- Utility: Shared vehicle pricing
function GetVehiclePriceFromShared(model)
    for _, v in pairs(QBCore.Shared.Vehicles) do
        if v.model == model then return v.price or 0 end
    end
    return 0
end
