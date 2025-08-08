fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'MacaroniandBeans'
description 'Used Car Dealership Script'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'
server_script 'server.lua'

dependencies {
    'ox_lib',
    'qb-core',
    'ox_target',
    'ox_inventory'
}
