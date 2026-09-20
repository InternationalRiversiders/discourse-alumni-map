# frozen_string_literal: true
module DiscourseAlumniMap
  module UserLifecycle
    def self.archived_users(user_id)
      Legacy.where(source: 'User').where("data->>'externalUserId' = ?", user_id.to_s)
    end
    def self.archive(user_id)
      users=archived_users(user_id)
      ids=users.pluck(:legacy_id)
      profiles=Legacy.where(source:'AlumniProfile').where("data->>'userId' IN (?)",ids)
      {user:users.pluck(:data),profiles:profiles.pluck(:data)}
    end
    def self.purge(user_id)
      return unless Profile.table_exists?
      Record.transaction do
        Shared.lock("user:#{user_id}")
        profile_ids=Profile.where(user_id:user_id).pluck(:id)
        users=archived_users(user_id)
        ids=users.pluck(:legacy_id)
        Legacy.where(source:'AlumniProfile').where("data->>'userId' IN (?)",ids).delete_all if ids.any?
        Legacy.where(target_kind:'Profile',target_id:profile_ids).delete_all
        users.delete_all
        Audit.where(target_kind:'Profile',target_id:profile_ids).delete_all
        Audit.where(user_id:user_id).update_all(user_id:Discourse.system_user.id)
        Event.where(user_id:user_id).delete_all
        Notification.where(user_id:user_id,notification_type:Notification.types[:custom]).where("data::jsonb->>'river_app' = 'alumni_map'").destroy_all
        Command.where(user_id:user_id).delete_all
        Media.where(user_id:user_id).delete_all
        Profile.where(user_id:user_id).delete_all
      end
    end
    def self.merge(source,target)
      return unless Profile.table_exists?
      Record.transaction do
        [source.id,target.id].sort.each { |id| Shared.lock("user:#{id}") }
        profile=Profile.find_by(user_id:source.id)
        # One card per forum account. Keep the target's own card on conflict.
        # A transferred card is private until the surviving owner opts in again.
        if profile && !Profile.exists?(user_id:target.id)
          profile.update!(user_id:target.id,published:false,show_username:false)
          # Purge the superseded import copy rather than linking old identity data.
          Legacy.where(target_kind:'Profile',target_id:profile.id).delete_all
        end
        purge(source.id)
      end
    end
  end
end

# Account privacy events must still clean up stored data when the feature is disabled.
DiscourseEvent.on(:user_destroyed) { |user| DiscourseAlumniMap::UserLifecycle.purge(user.id) }
DiscourseEvent.on(:user_anonymized) { |user:, **_| DiscourseAlumniMap::UserLifecycle.purge(user.id) }
DiscourseEvent.on(:merging_users) { |source,target| DiscourseAlumniMap::UserLifecycle.merge(source,target) }
