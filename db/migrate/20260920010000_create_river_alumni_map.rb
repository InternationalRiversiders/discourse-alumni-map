# frozen_string_literal: true
class CreateRiverAlumniMap < ActiveRecord::Migration[7.2]
  def change
    create_table :river_alumni_map_commands do |t|
      t.bigint :user_id, null: false
      t.string :key, null: false
      t.string :fingerprint, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :river_alumni_map_commands, [:user_id, :key], unique: true
    create_table :river_alumni_map_events do |t|
      t.bigint :user_id, null: false
      t.string :key, null: false
      t.string :text, null: false
      t.string :path, null: false
      t.bigint :notification_id
      t.timestamps
    end
    add_index :river_alumni_map_events, :key, unique: true
    create_table :river_alumni_map_audits do |t|
      t.bigint :user_id, null: false
      t.string :action, null: false
      t.string :target_kind
      t.bigint :target_id
      t.string :reason, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    create_table :river_alumni_map_legacies do |t|
      t.string :source, null: false
      t.string :legacy_id, null: false
      t.string :target_kind
      t.bigint :target_id
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :river_alumni_map_legacies, [:source, :legacy_id], unique: true
    create_table :river_alumni_map_media do |t|
      t.bigint :user_id, null: false
      t.string :token, null: false
      t.binary :bytes, null: false
      t.integer :size, null: false
      t.timestamps
    end
    add_index :river_alumni_map_media, :token, unique: true
    create_table :river_alumni_map_reactions do |t|
      t.bigint :user_id, null: false
      t.string :target_kind, null: false
      t.bigint :target_id, null: false
      t.integer :value, null: false
      t.timestamps
    end
    add_index :river_alumni_map_reactions, [:user_id, :target_kind, :target_id], unique: true, name: 'river_alumni_map_reaction_unique'
    add_check_constraint :river_alumni_map_reactions, 'value IN (-1,1)', name: 'river_alumni_map_reaction_value'
    create_table :river_alumni_map_reports do |t|
      t.bigint :user_id, null: false
      t.string :target_kind, null: false
      t.bigint :target_id, null: false
      t.string :reason, null: false
      t.datetime :handled_at
      t.timestamps
    end
    add_index :river_alumni_map_reports, [:user_id, :target_kind, :target_id], unique: true, name: 'river_alumni_map_report_unique'
    create_table :river_alumni_map_comments do |t|
      t.bigint :user_id, null: false
      t.string :target_kind, null: false
      t.bigint :target_id, null: false
      t.bigint :parent_id
      t.text :body, null: false
      t.boolean :anonymous, null: false, default: false
      t.string :status, null: false, default: 'visible'
      t.decimal :rating, precision: 3, scale: 1
      t.jsonb :media_ids, null: false, default: []
      t.timestamps
    end
    add_index :river_alumni_map_comments, [:target_kind, :target_id, :id], name: 'river_alumni_map_comment_target'
    add_foreign_key :river_alumni_map_comments, :river_alumni_map_comments, column: :parent_id
    add_check_constraint :river_alumni_map_comments, 'rating IS NULL OR (rating >= 0.5 AND rating <= 5)', name: 'river_alumni_map_comment_rating'
    create_table :river_alumni_map_profiles do |t|
      t.bigint :user_id, null: false
      t.string :nickname, null: false
      t.boolean :published, null: false, default: false
      t.boolean :show_username, null: false, default: false
      t.string :status, null: false, default: 'visible'
      t.string :hidden_reason
      t.string :country
      t.string :province
      t.string :city
      t.decimal :latitude, precision: 8, scale: 4
      t.decimal :longitude, precision: 8, scale: 4
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :river_alumni_map_profiles, :user_id, unique: true
  end
end
