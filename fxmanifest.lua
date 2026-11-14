fx_version 'cerulean'
game 'gta5'

name 'bakery_barnfind'
author 'Bakery'
description 'Discover abandoned cars, restore them by hand, and drive them out.'
version '0.3.0'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'web/dist/THIRD_PARTY_NOTICES.md',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/barn_layout.lua',
}

client_scripts {
    'client/tuning.lua',
    'shared/pull_door_curve.lua',
    'client/ui.lua',
    'client/bridge.lua',
    'client/cutscene.lua',
    'client/barn.lua',
    'client/gizmo.lua',
    'client/admin.lua',
    'client/wheels.lua',
    'client/glass.lua',
    'client/oil.lua',
    'client/body.lua',
    'client/finds.lua',
    'client/runtime.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/requests.lua',
    'server/bridge.lua',
    'server/store.lua',
    'server/found.lua',
    'server/restore.lua',
    'server/admin.lua',
}

-- Barn shell + two hinged doors (stream/bk_barn_*.ydr), shared textures in stream/bk_barn.ytd,
-- and the custom two-handed door-pull ped clip (stream/bk_barnfind@doors.ycd)
data_file 'DLC_ITYP_REQUEST' 'stream/bk_barn.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/bk_jack.ytyp'   -- the trolley jack and oil filter (props_src/build_jack.py)

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
    'kq_link',
}

escrow_ignore {
    'config.lua',
    'client/bridge.lua',
    'server/bridge.lua',
}
