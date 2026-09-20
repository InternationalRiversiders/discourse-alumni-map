# frozen_string_literal: true
module DiscourseAlumniMap
  module Locations
    ROOT = File.expand_path('../data/locations', __dir__)
    COUNTRIES = JSON.parse(File.read(File.join(ROOT, 'countries.json'))).freeze
    KNOWN = JSON.parse(File.read(File.join(ROOT, 'known-cities.json'))).freeze
    def self.catalog(code)
      return [] unless COUNTRIES.any? { |c| c['code'] == code }
      # Cache per country, never accept a client-supplied filesystem path.
      Discourse.cache.fetch("alumni-locations-v1:#{code}", expires_in: 1.day) do
        JSON.parse(File.read(File.join(ROOT, "#{code}.json")))
      end
    end
    def self.options(code, state = nil)
      return COUNTRIES if code.blank?
      states = catalog(code)
      state.blank? ? states.map { |s| s.slice('code', 'name') } : states.find { |s| s['code'] == state }&.fetch('cities', []) || []
    end
    def self.coordinates(country, province, city)
      known = KNOWN.find { |c| c.values_at('country', 'province', 'city') == [country, province.to_s, city] }
      return known.values_at('lat', 'lng') if known
      code = COUNTRIES.find { |c| c['name'] == country }&.fetch('code')
      entry = catalog(code).find { |s| s['name'] == province }&.fetch('cities', [])&.find { |c| c['name'] == city }
      entry && entry['lat'] && entry['lng'] ? entry.values_at('lat', 'lng') : nil
    end
  end
end
