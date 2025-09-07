local obs = obslua

-- ---------- state ----------
local g_props = nil
local g_settings = nil

local P_USE_CURRENT = "use_current_scene"
local P_SCENE       = "scene"
local P_QUERY       = "query"
local P_MATCHES     = "matches"

local B_MOVE_TOP    = "btn_move_selected_top"
local B_HIDE_ALL    = "btn_hide_all"

-- ---------- utils ----------
local function log(fmt, ...)
    obs.script_log(obs.LOG_INFO, string.format("[source_tools_min] "..fmt, ...))
end

local function get_current_scene_source()
    return obs.obs_frontend_get_current_scene()
end

local function get_scene_source_by_name(name)
    if not name or name == "" then return nil end
    local src = obs.obs_get_source_by_name(name)
    if not src then return nil end
    if obs.obs_source_get_type(src) ~= obs.OBS_SOURCE_TYPE_SCENE then
        obs.obs_source_release(src)
        return nil
    end
    return src
end

local function list_all_scenes()
    local scenes = {}
    local all = obs.obs_enum_sources()
    if all ~= nil then
        for _, s in ipairs(all) do
            if obs.obs_source_get_type(s) == obs.OBS_SOURCE_TYPE_SCENE then
                table.insert(scenes, obs.obs_source_get_name(s))
            end
        end
        obs.source_list_release(all)
    end
    table.sort(scenes, function(a,b) return a:lower() < b:lower() end)
    return scenes
end

local function get_selected_scene_source(settings)
    if obs.obs_data_get_bool(settings, P_USE_CURRENT) then
        return get_current_scene_source()
    end
    local name = obs.obs_data_get_string(settings, P_SCENE)
    if name == nil or name == "" or name == "<Current Scene>" then
        return get_current_scene_source()
    end
    return get_scene_source_by_name(name)
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

-- ---------- matching (plain, case-insensitive) ----------
local function compute_matches(settings)
    local query = (obs.obs_data_get_string(settings, P_QUERY) or ""):lower()
    local matches = {}

    local scene_src = get_selected_scene_source(settings)
    if scene_src == nil then return matches end

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
    obs.obs_property_list_add_string(prop, "<Current Scene>", "<Current Scene>")
    for _, s in ipairs(list_all_scenes()) do
        obs.obs_property_list_add_string(prop, s, s)
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
    if id == P_USE_CURRENT or id == P_SCENE or id == P_QUERY or id == P_MATCHES then
        refresh_matches_property(props, settings)
    end
    return true
end

-- ---------- actions ----------
local function with_scene_items(settings, fn)
    local scene_src = get_selected_scene_source(settings)
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
• Type to search sources in a scene (plain, case-insensitive).<br/>
• Select a match, then <i>Move Selected Match to TOP</i>.<br/>
• Or <i>Hide ALL Sources</i> in the scene.
]]
end

function script_properties()
    local props = obs.obs_properties_create()
    g_props = props

    -- Follow current scene
    local p_use_current = obs.obs_properties_add_bool(props, P_USE_CURRENT, "Use Current Scene")
    obs.obs_property_set_modified_callback(p_use_current, on_prop_modified)

    -- Scene picker
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

    -- Disable scene picker if following current
    local p_scene = obs.obs_properties_get(g_props, P_SCENE)
    local use_current = obs.obs_data_get_bool(settings, P_USE_CURRENT)
    if p_scene then obs.obs_property_set_enabled(p_scene, not use_current) end

    refresh_scene_list(p_scene, g_props, settings)
    refresh_matches_property(g_props, settings)
end

function script_defaults(settings)
    obs.obs_data_set_bool(settings, P_USE_CURRENT, true)
    obs.obs_data_set_string(settings, P_SCENE, "<Current Scene>")
    obs.obs_data_set_string(settings, P_QUERY, "")
    obs.obs_data_set_string(settings, P_MATCHES, "(no matches)")
end

function script_load(settings)
    g_settings = settings
end

function script_unload()
    -- nothing
end
