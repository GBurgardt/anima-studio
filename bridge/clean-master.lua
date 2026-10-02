-- Optional OBS Lua helper. Only changes visibility inside the chosen clean master.
-- Use shared CONTENT scenes: layouts update in both live and clean recordings.
local obs = obslua
local cfg = {}
local function follow()
  if obs.obs_frontend_get_current_scene_collection() ~= cfg.collection then return end
  local live = obs.obs_frontend_get_current_scene()
  local name = live and obs.obs_source_get_name(live) or ''
  if live then obs.obs_source_release(live) end
  local source = obs.obs_get_source_by_name(cfg.master)
  if not source then return end
  local scene = obs.obs_scene_from_source(source)
  if scene then
    for _, key in ipairs({'talk', 'screen', 'pause'}) do
      local item = obs.obs_scene_find_source(scene, cfg[key .. '_content'])
      if item then obs.obs_sceneitem_set_visible(item, name == cfg[key .. '_live']) end
    end
  end
  obs.obs_source_release(source)
end
function script_description()
  return 'Anima clean master. Configure shared content scenes and Source Record manually; see docs/CLEAN-RECORDING.md. Never starts a stream or recording.'
end
function script_properties()
  local p = obs.obs_properties_create()
  for _, key in ipairs({'collection','master','talk_live','talk_content','screen_live','screen_content','pause_live','pause_content'}) do
    obs.obs_properties_add_text(p, key, key, obs.OBS_TEXT_DEFAULT)
  end
  return p
end
function script_defaults(s)
  local defaults={collection='Anima',master='Clean Master',talk_live='Talk',talk_content='Talk Content',screen_live='Screen',screen_content='Screen Content',pause_live='Pause',pause_content='Pause Content'}
  for k,v in pairs(defaults) do obs.obs_data_set_default_string(s,k,v) end
end
function script_update(s)
  for _, key in ipairs({'collection','master','talk_live','talk_content','screen_live','screen_content','pause_live','pause_content'}) do cfg[key]=obs.obs_data_get_string(s,key) end
end
function script_load(s) script_update(s); obs.timer_add(follow,100) end
function script_unload() obs.timer_remove(follow) end
