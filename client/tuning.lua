-- Internal animation, layout, and minigame tuning.
Tuning = {}

Tuning.Barn = {
    Shell = 'bk_barn_shell',

    -- Each door is its own prop with its origin on the hinge axis. Hinge offsets are relative to the shell
    -- and come from props_src/build_barn.py (DOOR_HINGE_L / DOOR_HINGE_R) - change both together.
    -- openAngle: degrees the door swings to (negative = clockwise seen from above). Both swing outward.
    -- delay: ms after the open starts before this door begins to move, so the pair doesn't move in lockstep.
    Doors = {
        left  = { model = 'bk_barn_door_l', hinge = vec3(-2.66, -0.10, 0.0), openAngle = -112.0, delay = 0 },
        right = { model = 'bk_barn_door_r', hinge = vec3(2.66, -0.10, 0.0),  openAngle = 108.0,  delay = 420 },
    },

    -- Relative to the shell: where the player walks up to open it, and where the find sits inside.
    InteractPoint = vec3(0.0, -1.3, 1.0),
    CarSpot = BarnLayout.CarSpot,

    -- Clutter inside the barn: vanilla props, spawned locally with the barn (frozen, with collision).
    -- p = position relative to the barn (x right of the doorway, y into the barn); p.z = height of the prop's
    --     underside above the floor (0 = standing on it). With raw = true, p.z is the height of the model's origin
    --     instead (use it for props laid on their side, where the bounding box no longer says where the bottom is).
    -- r = rotation in degrees: pitch, roll, and heading relative to the barn (0 = facing into the barn).
    -- Keep clear: the car (x -1.1..1.1, y 3.9..8.9), the way out (x -1.8..1.8 in front of the car), and the cutscene
    -- cameras inside the barn (around x -2.2, y 9.6 and x 1.5..2.7, y 2.3..2.6).
    Dressing = {
        -- front left: tyres stacked flat, one leaning on the stack
        { model = 'prop_rub_tyre_03', p = vec3(-3.55, 1.15, 0.19), r = vec3(90.0, 0.0, 10.0), raw = true },
        { model = 'prop_rub_tyre_03', p = vec3(-3.52, 1.12, 0.53), r = vec3(90.0, 0.0, 47.0), raw = true },
        { model = 'prop_rub_tyre_02', p = vec3(-3.58, 1.18, 0.86), r = vec3(90.0, 0.0, 80.0), raw = true },
        { model = 'prop_rub_tyre_01', p = vec3(-2.85, 1.75, 0.42), r = vec3(0.0, -14.0, 62.0), raw = true },
        -- left wall: workbench, tool chest, work light; bits on the bench
        { model = 'prop_tool_bench02', p = vec3(-3.78, 4.55, 0.0), r = vec3(0.0, 0.0, 0.0) },
        { model = 'prop_tool_box_04', p = vec3(-3.85, 4.05, 1.0), r = vec3(0.0, 0.0, 85.0) },
        { model = 'prop_car_battery_01', p = vec3(-3.75, 5.05, 1.0), r = vec3(0.0, 0.0, 20.0) },
        { model = 'prop_oilcan_01a', p = vec3(-3.9, 5.45, 1.0), r = vec3(0.0, 0.0, -30.0) },
        { model = 'prop_toolchest_03', p = vec3(-3.85, 6.65, 0.0), r = vec3(0.0, 0.0, -90.0) },
        { model = 'prop_worklight_01a', p = vec3(-2.75, 3.45, 0.0), r = vec3(0.0, 0.0, 120.0) },
        -- left, behind the car: engine block on a pallet
        { model = 'prop_pallet_01a', p = vec3(-3.35, 8.1, 0.0), r = vec3(0.0, 0.0, 90.0) },
        { model = 'prop_car_engine_01', p = vec3(-3.35, 8.1, 0.26), r = vec3(0.0, 0.0, 70.0) },
        -- back left: drums, cans, an old bit of farm kit
        { model = 'prop_barrel_01a', p = vec3(-3.85, 10.9, 0.0), r = vec3(0.0, 0.0, 0.0) },
        { model = 'prop_barrel_01a', p = vec3(-3.25, 11.25, 0.0), r = vec3(0.0, 0.0, 140.0) },
        { model = 'prop_barrel_02a', p = vec3(-3.75, 10.25, 0.0), r = vec3(0.0, 0.0, 60.0) },
        { model = 'prop_oilcan_01a', p = vec3(-3.1, 10.55, 0.0), r = vec3(0.0, 0.0, 15.0) },
        { model = 'prop_jerrycan_01a', p = vec3(-2.95, 10.95, 0.0), r = vec3(0.0, 0.0, -50.0) },
        { model = 'prop_old_farm_01', p = vec3(-1.35, 10.95, 0.0), r = vec3(0.0, 0.0, 20.0) },
        -- front right: hay bales and feed sacks
        { model = 'prop_haybale_02', p = vec3(3.7, 1.6, 0.0), r = vec3(0.0, 0.0, 0.0) },
        { model = 'prop_haybale_01', p = vec3(3.75, 1.3, 1.31), r = vec3(0.0, 0.0, 8.0) },
        { model = 'prop_feed_sack_01', p = vec3(3.55, 3.35, 0.0), r = vec3(0.0, 0.0, 30.0) },
        -- right wall: panels and wheels leaning on the boards
        { model = 'prop_car_door_01', p = vec3(4.05, 4.2, 0.0), r = vec3(0.0, -12.0, 90.0) },
        { model = 'prop_car_bonnet_01', p = vec3(4.05, 5.35, 0.0), r = vec3(0.0, -10.0, 90.0) },
        { model = 'prop_wheel_tyre', p = vec3(3.95, 3.55, 0.35), r = vec3(0.0, -12.0, 90.0), raw = true },
        { model = 'prop_wheel_03', p = vec3(3.6, 5.95, 0.39), r = vec3(0.0, 8.0, 75.0), raw = true },
        -- right, beside the car: engine hoist
        { model = 'prop_engine_hoist', p = vec3(2.9, 7.4, 0.0), r = vec3(0.0, 0.0, 0.0) },
        -- back: shelving behind the car, ladder against the wall, pallet stack in the corner
        { model = 'prop_shelves_01', p = vec3(0.6, 11.4, 0.0), r = vec3(0.0, 0.0, 180.0) },
        -- on the shelves (shelf surfaces at 0.08, 0.74, 1.31 and 1.86 m)
        { model = 'prop_cardbordbox_04a', p = vec3(-0.15, 11.42, 0.085), r = vec3(0.0, 0.0, 6.0) },
        { model = 'prop_gascyl_01a', p = vec3(1.25, 11.4, 0.085), r = vec3(0.0, 0.0, 40.0) },
        { model = 'prop_paints_can01', p = vec3(-0.35, 11.38, 0.74), r = vec3(0.0, 0.0, 0.0) },
        { model = 'prop_paints_can01', p = vec3(-0.08, 11.46, 0.74), r = vec3(0.0, 0.0, 70.0) },
        { model = 'prop_cardbordbox_02a', p = vec3(1.1, 11.42, 0.74), r = vec3(0.0, 0.0, 85.0) },
        { model = 'prop_tool_box_02', p = vec3(0.35, 11.4, 1.315), r = vec3(0.0, 0.0, 180.0) },
        { model = 'prop_oilcan_02a', p = vec3(1.4, 11.45, 1.315), r = vec3(0.0, 0.0, 160.0) },
        { model = 'prop_cardbordbox_02a', p = vec3(-0.25, 11.42, 1.315), r = vec3(0.0, 0.0, 95.0) },
        { model = 'prop_bucket_01a', p = vec3(1.2, 11.4, 1.865), r = vec3(0.0, 0.0, 0.0) },
        { model = 'prop_byard_ladder01', p = vec3(-2.25, 11.35, 1.73), r = vec3(-14.0, 0.0, 0.0), raw = true },
        { model = 'prop_pallet_pile_01', p = vec3(3.45, 10.1, 0.0), r = vec3(0.0, 0.0, 90.0) },
        -- floor clutter
        { model = 'prop_carcreeper', p = vec3(-1.75, 3.2, 0.0), r = vec3(0.0, 0.0, 25.0) },
        { model = 'prop_carjack', p = vec3(1.7, 9.6, 0.0), r = vec3(0.0, 0.0, -70.0) },
        { model = 'prop_jerrycan_01a', p = vec3(2.35, 4.6, 0.0), r = vec3(0.0, 0.0, 35.0) },
        { model = 'prop_tool_box_06', p = vec3(-2.95, 5.85, 0.0), r = vec3(0.0, 0.0, 75.0) },
    },
}

-- Door swing curve. t is ms from the door's start, v is how far open (0 closed, 1 = openAngle).
-- ease is applied to the segment ending at that key: 'linear', 'in', 'out', 'inout'.
-- The shape: rattle against the latch, a heavy slow start, momentum, a small overshoot and a settle.
Tuning.DoorOpenCurve = {
    { t = 0,    v = 0.0 },
    { t = 160,  v = 0.010, ease = 'out' },
    { t = 300,  v = 0.002, ease = 'in' },
    { t = 450,  v = 0.016, ease = 'out' },
    { t = 620,  v = 0.008, ease = 'inout' },
    { t = 1900, v = 0.50,  ease = 'in' },
    { t = 2950, v = 1.035, ease = 'out' },
    { t = 3400, v = 0.985, ease = 'inout' },
    { t = 3750, v = 1.0,   ease = 'inout' },
}

Tuning.DoorCloseCurve = {
    { t = 0,    v = 1.0 },
    { t = 1600, v = 0.15, ease = 'inout' },
    { t = 2000, v = 0.0,  ease = 'in' },
    { t = 2150, v = 0.012, ease = 'out' },
    { t = 2300, v = 0.0,  ease = 'in' },
}

Tuning.Text = {
    search = '[E] Open the barn',
    searchTarget = 'Open the barn',
    open = '[E] Open the doors',
    openTarget = 'Open the doors',
    close = '[E] Close the doors',
    closeTarget = 'Close the doors',
    skip = 'Skip',
    alreadyFound = 'Someone has already been through this barn.',
    cooldown = 'This barn has been emptied. Come back in %s.',
    empty = 'There is nothing in this barn.',
    tooFar = 'Get closer to the doors.',
    busy = 'Not right now.',
}

-- How rough the find looks. Damage points are relative to the car (x right, y forward, z up), damage is GTA units.
Tuning.Wreck = {
    Damage = {
        { offset = vec3(0.6, 2.0, 0.2),   damage = 380.0, radius = 900.0 },
        { offset = vec3(-0.9, -0.4, 0.3), damage = 260.0, radius = 700.0 },
        { offset = vec3(-0.3, -2.2, 0.1), damage = 320.0, radius = 800.0 },
        { offset = vec3(0.2, 0.3, 0.8),   damage = 180.0, radius = 600.0 },
    },
}

-- ---------------------------------------------------------------- cutscene
-- Everything is relative to the barn: x to the right of the doorway, y into the barn, z up from the floor.
-- A shot's camera moves from `from` to `to` over its duration, looking from `look` to `lookTo`, with `ease`.
-- Shot times are in ms from the start of the cutscene; the next shot starts where the previous one ends.
Tuning.Cutscene = {
    SkipKey = 194,              -- control index to skip (194 = Backspace)
    SkipKeyLabel = 'Backspace', -- shown in the hint, bottom right
    Letterbox = 0.11,           -- height of each black bar, fraction of the screen
    PlayerStart = vec4(-1.2, -5.6, 0.0, 0.0),   -- where the player is placed (behind the fade) to walk up
    WatchMark = vec4(0.0, -1.2, 0.0, 0.0),       -- where the pull clip leaves them (and where a skip puts them)
    -- Custom two-handed clip (stream/bk_barnfind@doors.ycd, built by props_src/anim/build_door_anim.py): grab both
    -- handles, haul the doors open, let go and fling them wide. Its start mark and the doors' angle through it are
    -- generated into shared/pull_door_curve.lua, so the doors stay locked to the hands.
    PullAnim = { dict = 'bk_barnfind@doors', clip = 'open_doors' },
    AdmireAnim = { dict = 'anim@amb@carmeet@checkout_car@male_a@idles', clip = 'idle_b' },

    Shots = {
        { name = 'approach', duration = 3600, fov = 42.0, ease = 'inout', shake = 0.15,
          from = vec3(-6.4, -9.2, 0.9), to = vec3(-4.6, -7.6, 1.15),
          look = vec3(0.0, 0.0, 2.6), lookTo = vec3(0.0, 0.0, 2.3) },
        { name = 'pull', duration = 2600, fov = 42.0, ease = 'inout', shake = 0.25,      -- ends on the release
          from = vec3(1.9, -2.3, 1.45), to = vec3(2.35, -3.2, 1.4),
          look = vec3(0.05, -0.5, 1.15), lookTo = vec3(0.0, -1.0, 1.2) },
        { name = 'from_the_dark', duration = 3700, fov = 46.0, ease = 'inout', shake = 0.2,
          from = vec3(-2.2, 9.6, 0.75), to = vec3(-1.9, 9.0, 0.85),
          look = vec3(0.0, -1.0, 1.9), lookTo = vec3(0.0, -1.0, 1.8) },
        { name = 'reveal', duration = 4800, fov = 40.0, fovTo = 33.0, ease = 'inout', shake = 0.2,
          from = vec3(1.25, -5.4, 1.75), to = vec3(1.0, -3.9, 1.7),
          look = vec3(0.0, 6.4, 0.8), lookTo = vec3(0.0, 6.2, 0.75) },
        { name = 'hero', duration = 5200, fov = 38.0, ease = 'inout', shake = 0.15,
          from = vec3(2.7, 2.6, 0.55), to = vec3(1.5, 2.3, 0.8),
          look = vec3(0.2, 5.0, 0.55), lookTo = vec3(0.0, 6.0, 0.6) },
    },
    BlendOut = 1600,            -- ms to ease back to the gameplay camera

    -- Warm light from the doorway onto the find while it's revealed (drawn only during the cutscene)
    Light = { from = vec3(0.0, -1.0, 4.0), to = vec3(0.0, 6.4, 0.3), color = { 255, 214, 160 },
              distance = 14.0, brightness = 9.0, roundness = 4.0, radius = 30.0, falloff = 12.0 },

    Particles = {
        dustBurst = { asset = 'core', name = 'ent_dst_dust', scale = 1.4 },          -- at the doors as they swing
        motes = { asset = 'core', name = 'ent_amb_dust_motes', scale = 1.0 },        -- floating in the light
        flies = { asset = 'core', name = 'ent_amb_fly_swarm', scale = 0.8 },         -- over the find
    },
}


-- ---------------------------------------------------------------- restoring
-- Bringing a find back, by hand, on the car in the barn. The steps run in this order (switched on and off, and the
-- items each one uses, in /barnadmin): tyres and wheels, windows, oil and filter, bodywork, start it up. Once it
-- runs, the car is the finder's: in their garage, keys in hand, and they drive it out.
--
-- Wheels: roll the trolley jack under the car and pump it up, undo the nuts, pull the old wheel off, line the new
-- one up on the studs and push it on, do the nuts up in a star pattern and let the car down. All four wheels.
Tuning.Restore = {
    Wheels = {
        OldProp = 'prop_wheel_03',             -- the rusty wheel left lying by the car once it is off
        NewProp = 'prop_wheel_01',             -- the new wheel you line up and push on
        GunProp = 'imp_prop_impact_driver_01a',
        Nuts = 5,                              -- wheel nuts per wheel
        NutCircle = 0.30,                      -- nut circle radius, as a share of the rim radius
        JackLift = 0.24,                       -- metres the jacked corner comes up (enough for a new tyre to clear)
        Pumps = 8,                             -- strokes of the handle: the first few bring the saddle up to the car
        AlignTolerance = 7.0,                  -- degrees either side of the studs that still slides on
        -- Tightening: hold on a nut and let go while the torque needle is in this band (0-1 of a full turn).
        TorqueBand = { 0.74, 0.90 },
        LoosenMs = 650,                        -- how long the gun has to run to undo one nut
        TightenMs = 1300,                      -- time for the needle to sweep from 0 to 1
        Anims = {
            kneel = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 },
        },
        -- The trolley jack (props_src/build_jack.py). Its geometry must match the models: ArmPivot, ArmLength,
        -- SaddleTop and HandlePivot are ARM_PIVOT, ARM_LEN, SADDLE_TOP and HANDLE_PIVOT there.
        Jack = {
            Models = { base = 'bk_jack_base', arm = 'bk_jack_arm', saddle = 'bk_jack_saddle', handle = 'bk_jack_handle' },
            ArmPivot = vec3(0.0, -0.20, 0.11),
            ArmLength = 0.50,
            SaddleTop = 0.075,
            HandlePivot = vec3(0.0, -0.29, 0.145),
            RestAngle = 4.0,                   -- arm angle when it is all the way down (degrees)
            MaxAngle = 62.0,
            HandleRest = -20.0,                -- handle angle at rest (degrees, negative is up): kneeling height
            HandleStroke = 16.0,               -- how far each pump pushes it down
            -- where it goes under the car, relative to the wheel's centre: inwards from the wheel's outside edge,
            -- and along the car away from the wheel (behind a front wheel, in front of a rear one)
            In = 0.10,
            Along = 0.62,
            RollIn = 0.55,                     -- metres it rolls in from
        },
    },
    -- ------------------------------------------------------------ restoring: glass
    -- Replacing the glass: every smashed window gets its own prompt on the car. Picking one walks you up to it,
    -- clears the broken glass and fits the new pane.
    Glass = {
        ClearMs = 4000,                        -- clearing out the broken glass
        FitMs = 6000,                          -- fitting the new pane
        Anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    },
    -- ------------------------------------------------------------ restoring: oil and filter
    -- An oil and filter change: a trolley jack under the middle of each side to get the car up level, then on your
    -- back under it, spin the old filter off and the new one on, and let it down.
    Oil = {
        FilterProp = 'bk_oil_filter',          -- props_src/build_jack.py; origin on the top (the face that seals)
        FilterLength = 0.09,                   -- these two must match the model (FILTER_LEN, FILTER_R)
        FilterRadius = 0.048,
        FilterSide = 0.18,                     -- metres to the side of the engine bone it hangs
        Turns = 3,                             -- turns to spin a filter off, or on
        ThreadDrop = 0.03,                     -- how far it comes down the thread over those turns
        Lift = 0.26,                           -- metres each side comes up
        Pumps = 8,
        JackIn = 0.30,                         -- how far in from the car's side the jack goes under
        LieOut = -0.30,                        -- where you lie: your hips, metres out from the car's side (- is under)
        LieHeading = 180.0,                    -- the pose lies head-first the way the ped faces away
        WheelClear = 0.75,                     -- keep this far along the car from a wheel when you lie down
        UnderCam = { out = 0.30, back = 0.22, up = 0.14, fov = 45.0 },   -- the camera under the car
        Anims = {
            under = { dict = 'amb@world_human_vehicle_mechanic@male@base', clip = 'base', flag = 1 },
        },
    },
    -- ------------------------------------------------------------ restoring: bodywork
    -- Bodywork: the car is dented and grimy on each face (left, right, front, rear). Grind each face back to bare
    -- metal (a percentage of the face covered); once ground the face is done and its dents come out.
    Body = {
        -- The tools follow the cursor on the panel, disc flat against it. For each model: Disc is the middle of the
        -- disc's working face (model space; the disc faces down -Z), Body the way the rest of the tool runs from it,
        -- Tilt how far the body leans back off the panel (degrees), Lift how far it comes off when you let go,
        -- Shake how hard it buzzes while it runs (metres).
        Tools = {
            grind = { Model = 'tr_prop_tr_grinder_01a', Disc = vec3(-0.04, 0.17, -0.07), Body = vec3(0.0, -1.0, 0.0), Tilt = 25.0, Lift = 0.04, Shake = 0.003 },
        },
        Patches = { side = 6, ['end'] = 4 },    -- points per face the camera frames and the dents go at: sides, ends
        MinGap = 0.24,                         -- metres apart they have to be, at least
        Rays = 120,                            -- rays cast at each face to find its bodywork
        AvoidBones = {                         -- patches keep clear of these (lights, plates)
            'headlight_l', 'headlight_r', 'taillight_l', 'taillight_r', 'brakelight_l', 'brakelight_r', 'brakelight_m',
            'indicator_lf', 'indicator_rf', 'indicator_lr', 'indicator_rr', 'reversinglight_l', 'reversinglight_r',
            'platelight', 'numberplate',
        },
        AvoidRadius = 0.22,
        Band = { 0.20, 0.52 },                 -- height band they are looked for in, as a share of the car's height
        -- Grinding is a percentage of the face: it is split into WorkCell-metre squares (wherever the rays found
        -- bodywork), and each square fills while the grinder moves over it, up to WorkCellMs of work.
        WorkCell = 0.25,
        WorkCellMs = { grind = 260 },          -- time on each square to clear it (forgiving: a few quick passes do)
        WorkMinMove = 0.002,                   -- metres a frame the tool has to be moving to count
        WorkDone = 0.6,                        -- share of the face that has to be worked for the pass to be done
        CamFov = 50.0,
        Dents = 2,                             -- knocks per face
        DentDamage = 220.0,
        DentRadius = 60.0,
        BodyHealth = 350,                      -- body health while every face is still rough
        Fx = {
            grind = { asset = 'core', name = 'ent_brk_sparking_wires', scale = 0.6 },
        },
    },
    -- ------------------------------------------------------------ restoring: the first start
    -- Get in and start it: a skill check while it cranks (a needle sweeping round a ring, tap as it crosses the mark),
    -- Hits in a row and it catches; a miss and it coughs and the count starts again.
    Ignition = {
        Hits = 3,                              -- in a row
        Speed = 0.85,                          -- turns of the needle a second, at first
        SpeedUp = 0.18,                        -- and this much faster after each hit
        Zone = 34,                             -- degrees wide, the mark to hit
    },
    Text = {
        ignition = '[E] Start it up',            ignitionTarget = 'Start it up',
        ignitionDone = 'It runs.',
        body_grind = '[E] Grind back the %s',    body_grindTarget = 'Grind back the %s',
        bodyLeft = '%s done (%d of %d).',
        bodyDone = 'The bodywork is done. Took %s.',
        glassReplace = '[E] Replace the %s',   glassReplaceTarget = 'Replace the %s',
        glassClearing = 'Clearing the broken %s',
        glassFitting = 'Fitting the new %s',
        oil_jack = '[E] Jack this side up',  oil_jackTarget = 'Jack this side up',
        oil_under = '[E] Get under the car', oil_underTarget = 'Get under the car',
        oil_lower = '[E] Let this side down', oil_lowerTarget = 'Let this side down',
        oilFilterDone = 'New filter on. Let the car down.',
        oilDone = 'Oil and filter changed. Took %s.',
        glassLeft = 'Glass in. %d to go.',
        glassDone = 'All the glass is in. Took %s.',
        jack = '[E] Jack it up',              jackTarget = 'Jack it up',
        loosen = '[E] Undo the wheel nuts',   loosenTarget = 'Undo the wheel nuts',
        pull = '[E] Pull the wheel off',      pullTarget = 'Pull the wheel off',
        fit = '[E] Fit the new wheel',        fitTarget = 'Fit the new wheel',
        tighten = '[E] Do the nuts up',       tightenTarget = 'Do the nuts up',
        lower = '[E] Let it down',            lowerTarget = 'Let it down',
        jackInUse = 'The jack is under another wheel. Let that one down first.',
        wheelsLeft = 'Wheel done. %d to go.',
        allDone = 'All four wheels are on. Took %s.',
        -- restoring a find in the barn
        restoreStep = '[E] Restore: %s',            restoreStepTarget = 'Restore: %s',
        restoreClaim = '[E] Take it out of the barn', restoreClaimTarget = 'Take it out of the barn',
        restoreNeeds = 'Needs %s.',
        restoreMissing = 'You need %dx %s for this.',
        restoreStepDone = '%s done. Next: %s.',
        restoreAllDone = 'Fully restored. Take it out of the barn.',
        restoreYours = 'It is yours. Drive it out.',
        restoreHandoff = 'The vehicle is yours, but the handoff could not finish. Contact an admin if you cannot access it.',
        restoreNotYours = 'Only the one who found it can restore it.',
        restoreStopped = 'You walked away. That step was not finished.',
        restoreFinishing = 'Finishing up: %s',
        notFourWheels = 'This car does not have four wheels to change.',
    },
}
