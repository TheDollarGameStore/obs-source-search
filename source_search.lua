local obs = obslua

-- ---------- state ----------
local g_props = nil
local g_settings = nil

local P_SCENE       = "scene"
local P_QUERY       = "query"
local P_MATCHES     = "matches"

local B_MOVE_TOP    = "btn_move_selected_top"
local B_HIDE_ALL    = "btn_hide_all"

-- ---------- utils ----------
local function log(fmt, ...)
    obs.script_log(obs.LOG_INFO, string.format("[source_tools_min] "..fmt, ...))
end

-- Frontend-safe: enumerate scenes via frontend list (more reliable than obs_enum_sources)
local function list_all_scenes()
    local names = {}
    local arr = obs.obs_frontend_get_scenes()
    if not arr or #arr == 0 then
        log("No scenes found via obs_frontend_get_scenes().")
        return names
    end
    for _, src in ipairs(arr) do
        if src ~= nil then
            local nm = obs.obs_source_get_name(src)
            if nm and nm ~= "" then table.insert(names, nm) end
            -- Release each retained scene source from the frontend list
            obs.obs_source_release(src)
        end
    end
    table.sort(names, function(a,b) return a:lower() < b:lower() end)
    return names
end

local function get_scene_source_by_name(name)
    if not name or name == "" then return nil end
    local src = obs.obs_get_source_by_name(name)
    if not src then
        log("get_scene_source_by_name: '%s' not found.", name)
        return nil
    end
    if obs.obs_source_get_type(src) ~= obs.OBS_SOURCE_TYPE_SCENE then
        log("Source '%s' exists but is not a Scene type.", name)
        obs.obs_source_release(src)
        return nil
    end
    return src
end

local function get_scene_items(scene_src)
    if scene_src == nil then return {} end
    local scene = obs.obs_scene_from_source(scene_src)
    if scene == nil then return {} end
    local items = obs.obs_scene_enum_items(scene)
    local out = {}
    if items ~= nil then
        for _, it in ipairs(items) do
            local src = obs.obs_sceneitem_get_source(it)
            local nm = src and obs.obs_source_get_name(src) or "<unnamed>"
            table.insert(out, { item = it, source = src, name = nm })
        end
        obs.sceneitem_list_release(items)
    end
    return out
end

-- If user hasn't picked a scene yet, auto-select the first available (once)
local function ensure_scene_selected(settings)
    local chosen = obs.obs_data_get_string(settings, P_SCENE)
    if chosen and chosen ~= "" then return end
    local all = list_all_scenes()
    if #all > 0 then
        obs.obs_data_set_string(settings, P_SCENE, all[1])
        log("Auto-selected first scene: %s", all[1])
    else
        log("No scenes available to auto-select.")
    end
end

-- ---------- matching (plain, case-insensitive) ----------
local function compute_matches(settings)
    local query = (obs.obs_data_get_string(settings, P_QUERY) or ""):lower()
    local matches = {}

    local name = obs.obs_data_get_string(settings, P_SCENE)
    if not name or name == "" then
        log("compute_matches: No scene selected.")
        return matches
    end

    local scene_src = get_scene_source_by_name(name)
    if scene_src == nil then
        log("compute_matches: Selected scene '%s' not found.", name or "<nil>")
        return matches
    end

    local items = get_scene_items(scene_src)
    for _, rec in ipairs(items) do
        if query == "" or rec.name:lower():find(query, 1, true) ~= nil then
            table.insert(matches, rec)
        end
    end

    obs.obs_source_release(scene_src)
    return matches
end

-- ---------- UI refresh ----------
local function refresh_scene_list(prop, props, settings)
    if not prop then return end
    obs.obs_property_list_clear(prop)

    local scenes = list_all_scenes()
    if #scenes == 0 then
        obs.obs_property_list_add_string(prop, "(no scenes found)", "")
        return
    end
    for _, s in ipairs(scenes) do
        obs.obs_property_list_add_string(prop, s, s)
    end

    -- Keep selected value if still present; otherwise pick first
    local current = obs.obs_data_get_string(settings, P_SCENE)
    local has = false
    for _, s in ipairs(scenes) do
        if s == current then has = true; break end
    end
    if not has then
        obs.obs_data_set_string(settings, P_SCENE, scenes[1])
        log("Scene selection updated to: %s", scenes[1])
    end
end

local function refresh_matches_property(props, settings)
    local list_prop = obs.obs_properties_get(props, P_MATCHES)
    if not list_prop then return end

    local prev = obs.obs_data_get_string(settings, P_MATCHES)
    obs.obs_property_list_clear(list_prop)

    local m = compute_matches(settings)
    if #m == 0 then
        obs.obs_property_list_add_string(list_prop, "(no matches)", "(no matches)")
        obs.obs_data_set_string(settings, P_MATCHES, "(no matches)")
        return
    end

    local restored = false
    for _, rec in ipairs(m) do
        obs.obs_property_list_add_string(list_prop, rec.name, rec.name)
        if rec.name == prev then restored = true end
    end
    if not restored then
        obs.obs_data_set_string(settings, P_MATCHES, m[1].name)
    end
end

local function on_prop_modified(props, prop, settings)
    local id = obs.obs_property_name(prop)
    if id == P_SCENE or id == P_QUERY or id == P_MATCHES then
        refresh_matches_property(props, settings)
    end
    return true
end

-- ---------- actions ----------
local function with_scene_items(settings, fn)
    local name = obs.obs_data_get_string(settings, P_SCENE)
    if not name or name == "" then
        log("with_scene_items: No scene selected.")
        return
    end
    local scene_src = get_scene_source_by_name(name)
    if not scene_src then return end

    local scene = obs.obs_scene_from_source(scene_src)
    if not scene then
        obs.obs_source_release(scene_src)
        return
    end

    local items = obs.obs_scene_enum_items(scene)
    if items ~= nil then
        fn(items)
        obs.sceneitem_list_release(items)
    end
    obs.obs_source_release(scene_src)
end

local function do_move_selected_to_top(settings)
    local selected = obs.obs_data_get_string(settings, P_MATCHES) or ""
    if selected == "" or selected == "(no matches)" then
        log("No selected match to move.")
        return
    end
    with_scene_items(settings, function(items)
        for _, it in ipairs(items) do
            local src = obs.obs_sceneitem_get_source(it)
            local name = src and obs.obs_source_get_name(src) or ""
            if name == selected then
                obs.obs_sceneitem_set_order(it, obs.OBS_ORDER_MOVE_TOP)
                log("Moved '%s' to TOP.", name)
                break
            end
        end
    end)
end

local function do_hide_all(settings)
    with_scene_items(settings, function(items)
        for _, it in ipairs(items) do
            obs.obs_sceneitem_set_visible(it, false)
        end
    end)
    log("All sources hidden.")
end

-- ---------- button callbacks ----------
local function cb_move_top(props, prop)
    do_move_selected_to_top(g_settings)
    return true
end

local function cb_hide_all(props, prop)
    do_hide_all(g_settings)
    return true
end

-- ---------- OBS script API ----------
function script_description()
    return [[
<b>Minimal Source Tools</b><br/>
• Pick a scene from the dropdown (mandatory).<br/>
• Type to search sources in that scene (plain, case-insensitive).<br/>
• Select a match, then <i>Move Selected Match to TOP</i>.<br/>
• Or <i>Hide ALL Sources</i> in the scene.
]]
end

function script_properties()
    local props = obs.obs_properties_create()
    g_props = props

    -- Scene picker (mandatory)
    local p_scene = obs.obs_properties_add_list(
        props, P_SCENE, "Scene",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING
    )
    refresh_scene_list(p_scene, props, g_settings or obs.obs_data_create())
    obs.obs_property_set_modified_callback(p_scene, on_prop_modified)

    -- Search box
    local p_query = obs.obs_properties_add_text(props, P_QUERY, "Search", obs.OBS_TEXT_DEFAULT)
    obs.obs_property_set_modified_callback(p_query, on_prop_modified)

    -- Matches (select one)
    local p_matches = obs.obs_properties_add_list(
        props, P_MATCHES, "Matches",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING
    )
    obs.obs_property_set_long_description(p_matches, "Select a matched source to move it to the top.")
    obs.obs_property_set_modified_callback(p_matches, on_prop_modified)

    -- Buttons
    obs.obs_properties_add_button(props, B_MOVE_TOP, "Move Selected Match to TOP", cb_move_top)
    obs.obs_properties_add_button(props, B_HIDE_ALL, "Hide ALL Sources", cb_hide_all)

    return props
end

function script_update(settings)
    g_settings = settings
    ensure_scene_selected(settings)

    local p_scene = obs.obs_properties_get(g_props, P_SCENE)
    refresh_scene_list(p_scene, g_props, settings)
    refresh_matches_property(g_props, settings)
end

function script_defaults(settings)
    obs.obs_data_set_string(settings, P_SCENE, "")
    obs.obs_data_set_string(settings, P_QUERY, "")
    obs.obs_data_set_string(settings, P_MATCHES, "(no matches)")
end

function script_load(settings)
    g_settings = settings
end

function script_unload()
    -- nothing
end
