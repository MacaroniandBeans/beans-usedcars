-- server.lua
local QBCore = exports['qb-core']:GetCoreObject()

local showroomInventory = {}
local displaySpots = {}

function GetVehiclePriceFromShared(model)
    for _, v in pairs(QBCore.Shared.Vehicles) do
        if v.model == model then return v.price or 0 end
    end
    return 0
end


-- Calculate used vehicle price
function CalculateUsedVehiclePrice(listPrice, mileage)
    local base = listPrice * 0.8
    local penalty = 0.0

    for _, tier in ipairs(Config.MileagePenalties) do
        if mileage >= tier.miles then
            penalty = tier.reduction
        else
            break
        end
    end

    return math.floor(base - (base * penalty))
end

lib.callback.register('beans-usedcars:server:BuyVehicle', function(source, plate)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return { success = false } end

    local result = exports.oxmysql:fetchSync('SELECT * FROM used_dealership WHERE plate = ?', { plate })
    if not result or not result[1] then return { success = false } end

    local row = result[1]
    local price = GetVehiclePriceFromShared(row.vehicle)

    -- Charge player
    if not Player.Functions.RemoveMoney("cash", price, "used-car-purchase") then
        return { success = false }
    end

    -- Transfer ownership
    exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, fuel, engine, body, state, depotprice, drivingdistance, glovebox, trunk, damage, financed, mileage, persisted, vinscratch) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.license,
        Player.PlayerData.citizenid,
        row.vehicle,
        row.hash,
        row.mods,
        row.plate,
        "legionsquare",
        100,
        1000,
        1000,
        1,
        0,
        row.mileage or 0,
        "[]",
        "[]",
        "[]",
        0,
        row.mileage or 0,
        1,
        row.vinscratch or 0
    })

    -- Delete from used lot
    exports.oxmysql:execute('DELETE FROM used_dealership WHERE plate = ?', { plate })

    -- ✅ Send full vehicle info back to client
    return {
        success = true,
        model = row.vehicle,
        plate = row.plate,
        mods = row.mods
    }
end)




-- Find open display spot
function GetFreeShowroomSpot()
    for i, coords in ipairs(Config.ShowroomSpots) do
        local taken = false

        for _, vehicle in pairs(showroomInventory) do
            if vehicle.coords then
                local vx, vy, vz = vehicle.coords.x, vehicle.coords.y, vehicle.coords.z
                local dx = math.abs(coords.x - vx)
                local dy = math.abs(coords.y - vy)
                local dz = math.abs(coords.z - vz)
                if dx < 1.0 and dy < 1.0 and dz < 1.5 then
                    taken = true
                    break
                end
            end
        end

        if not taken then
            return i, coords
        end
    end

    return nil, nil
end




-- Remove player-owned vehicle
function RemoveOwnership(plate)
    exports.oxmysql:execute('DELETE FROM player_vehicles WHERE plate = ?', { plate })
end





-- 🔧 Get used vehicle mod info for preview
lib.callback.register('beans-usedcars:server:GetUsedVehicleInfo', function(source, plate)
    local result = exports.oxmysql:fetchSync('SELECT * FROM used_dealership WHERE plate = ?', { plate })
    if not result or not result[1] then return nil end

    local row = result[1]
    local mods = {}

    if row.mods and type(row.mods) == "string" then
        local ok, decoded = pcall(json.decode, row.mods)
        if ok and type(decoded) == "table" then
            mods = decoded
        end
    end

    return {
        plate = row.plate,
        model = row.vehicle,
        mileage = tonumber(row.mileage or 0),
        price = tonumber(row.price or 0),
        engine = tonumber(mods.modEngine or -1),
        brakes = tonumber(mods.modBrakes or -1),
        transmission = tonumber(mods.modTransmission or -1),
        turbo = mods.modTurbo == true,
        suspension = tonumber(mods.modSuspension or -1),
        color1 = mods.color1
    }
end)









-- 💰 Sell vehicle
-- 💰 Sell vehicle
RegisterNetEvent("beans-usedcars:server:SellVehicle", function(plate, model, props)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    -- Get old data from player_vehicles
    local oldData = exports.oxmysql:fetchSync('SELECT * FROM player_vehicles WHERE plate = ?', { plate })
    if not oldData or not oldData[1] then return end
    local v = oldData[1]

    local mileage = tonumber(v.mileage or 0)
    local isScratch = tonumber(v.vinscratch or 0) == 1

    -- Get price from shared and calculate resale
    local listPrice = GetVehiclePriceFromShared(model) or 0
    local resalePrice = listPrice
    local payout = 0

    if isScratch then
        payout = math.floor(listPrice * Config.VINScratchSellPercent)
        resalePrice = math.floor(listPrice * Config.VINScratchResalePercent)
        TriggerClientEvent('ox_lib:notify', src, {
            title = "Shady Sale",
            description = "This VIN looks scratched... the dealer is only offering $" .. payout,
            type = "warning"
        })
    else
        payout = CalculateUsedVehiclePrice(listPrice, mileage)
        resalePrice = payout -- Save the same payout as resale price
    end

    -- 🧼 Clear out any old reference to this plate
    for index, p in pairs(displaySpots) do
        if p == plate then
            displaySpots[index] = nil
            showroomInventory[plate] = nil
            break
        end
    end

    -- Pay the player
    player.Functions.AddMoney("cash", payout, "used-car-sale")

    -- Save to used_dealership
    local modelHash = GetHashKey(model)
    local modelName = model:lower()
    local encodedMods = type(props) == "table" and json.encode(props) or "{}"

    exports.oxmysql:insert('INSERT INTO used_dealership (vehicle, hash, mods, plate, garage, fuel, engine, body, state, depotprice, drivingdistance, glovebox, trunk, damage, in_garage, mileage, persisted, vinscratch, price) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        modelName,
        modelHash,
        encodedMods,
        plate,
        "pillboxgarage",
        100,
        props.engineHealth or 1000,
        props.bodyHealth or 1000,
        1,
        0,
        mileage,
        "[]",
        "[]",
        "[]",
        true,
        mileage,
        1,
        isScratch and 1 or 0,
        resalePrice
    })

    -- Remove from player_vehicles
    exports.oxmysql:execute('DELETE FROM player_vehicles WHERE plate = ?', { plate })

    -- ✅ Spawn in showroom
-- ✅ Spawn in showroom
local spotIndex, coords = GetFreeShowroomSpot()
if not coords then
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Dealership Full',
        description = 'No space left on the lot. Come back later.',
        type = 'error'
    })
    return
end

local displayData = {
    model = model,
    plate = plate,
    price = resalePrice,
    coords = coords,
    mods = encodedMods,
    mileage = mileage
}

-- ✅ Track it
showroomInventory[plate] = displayData

TriggerClientEvent("beans-usedcars:client:SpawnVehicleForSale", -1, displayData)

end)








AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)

    local results = exports.oxmysql:fetchSync('SELECT * FROM used_dealership')
    local max = Config.MaxShowroomVehicles or #Config.ShowroomSpots
    local spawned = 0

    for i, v in ipairs(results) do
        if spawned >= max then break end

        local coords = Config.ShowroomSpots[spawned + 1]
        if coords then
            local displayData = {
                model = v.vehicle,
                plate = v.plate,
                price = v.price or 5000,
                coords = coords,
                mods = v.mods,
                mileage = v.mileage or 0
            }

            -- ✅ TRACK THIS SLOT
            showroomInventory[v.plate] = displayData

            TriggerClientEvent("beans-usedcars:client:SpawnVehicleForSale", -1, displayData)
            spawned += 1
        end
    end
end)



function loadUsedCarsToLot()
    local usedCars = exports.oxmysql:fetchSync('SELECT * FROM used_dealership', {})

    for _, car in pairs(usedCars or {}) do
        -- Make sure the data includes a valid spawn point
        if car.spawnCoords then
            local coords = json.decode(car.spawnCoords)
            TriggerClientEvent('beans-usedcars:client:SpawnVehicleForSale', -1, {
                model = car.vehicle,
                plate = car.plate,
                price = car.price,
                coords = coords
            })
        else
            print(("❌ Missing spawnCoords for %s"):format(car.plate))
        end
    end
end

RegisterNetEvent('beans-usedcars:server:TryRefillShowroom', function()
    local results = exports.oxmysql:fetchSync('SELECT * FROM used_dealership')
    local usedPlates = {}

    -- Check all vehicles already spawned
    for _, v in ipairs(results) do
        usedPlates[v.plate] = true
    end

    -- Spawn into open showroom spot
    for i = 1, #Config.ShowroomSpots do
        local plateTaken = false

        for _, v in ipairs(results) do
            if v.spawnIndex == i then
                plateTaken = true
                break
            end
        end

        if not plateTaken then
            for _, v in ipairs(results) do
                if not v.spawned then
                    TriggerClientEvent("beans-usedcars:client:SpawnVehicleForSale", -1, {
                        model = v.vehicle,
                        plate = v.plate,
                        price = v.price or 5000,
                        coords = Config.ShowroomSpots[i],
                        mods = v.mods,
                        mileage = v.mileage or 0
                    })
                    break
                end
            end
            break
        end
    end
end)

