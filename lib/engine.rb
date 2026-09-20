# frozen_string_literal: true
module ::DiscourseAlumniMap
  class Engine < ::Rails::Engine
    engine_name "discourse-alumni-map"
    isolate_namespace ::DiscourseAlumniMap
    config.root = File.expand_path("..", __dir__)
  end
end
