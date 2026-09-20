# frozen_string_literal: true
# name: discourse-alumni-map
# about: 校友地图 — Riverside native community application
# version: 0.1.0
# authors: Riverside
# required_version: 2026.9.0-latest

enabled_site_setting :alumni_map_enabled
register_asset "stylesheets/alumni_map.scss"
register_svg_icon "map-location-dot"
require_relative "lib/engine"

after_initialize do
  require_relative "lib/core"
  require_relative "lib/locations"
  require_relative "lib/business"
  require_relative "lib/importer"
  require_relative "lib/user_lifecycle"
  add_to_serializer(:current_user, :alumni_map_member) { SiteSetting.alumni_map_enabled && DiscourseAlumniMap::Access.member?(object) }

  Discourse::Application.routes.append { mount DiscourseAlumniMap::Engine, at: "/alumni-map" }
end
