Config = {}

Config.SellZone = {
    coords = vector3(-170.166, -1371.337, 30.026),
    size = vec3(6.0, 6.0, 3.0),
    rotation = 270.0
}


Config.SellPricePercent = 0.80          -- Normal sell rate
Config.VINScratchSellPercent = 0.30     -- If vinscratch = 1
Config.VINScratchResalePercent = 0.60   -- Dealership resale value if shady

-- Mileage tiers: if mileage > value, apply the % penalty
-- Mileage penalty tiers
Config.MileagePenalties = {
    { miles = 5000, reduction = 0.05 },
    { miles = 15000, reduction = 0.10 },
    { miles = 30000, reduction = 0.20 },
    { miles = 50000, reduction = 0.30 },
    { miles = 75000, reduction = 0.40 },
    { miles = 100000, reduction = 0.50 },
}

Config.ShowroomSpots = {
    vector4(-134.847, -1345.833, 29.701, 177.962),
    vector4(-138.994, -1346.182, 29.854, 180.637),
    vector4(-142.184, -1346.342, 29.872, 180.328),
    vector4(-146.466, -1346.609, 29.821, 180.631), -- 4 total
}

Config.MaxShowroomVehicles = 4

Config.DeliverySpawn = vector4(-140.126, -1369.837, 29.330, 119.428)
