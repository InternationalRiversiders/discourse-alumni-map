# frozen_string_literal: true
module DiscourseAlumniMap
  # The durable outbox is committed with the content. Queue failures must never
  # turn a successful save into an HTTP failure; the scheduled tick is a fallback.
  module Notifications
    def self.enabled? = SiteSetting.alumni_map_enabled && !SiteSetting.alumni_map_read_only
    def self.pending = Event.where(notification_id: nil).where('next_attempt_at <= ?', Time.current)

    def self.enqueue
      return unless enabled?
      if Discourse.redis.set('alumni_map:notification-enqueue', '1', nx: true, ex: 5)
        Jobs.enqueue(:discourse_alumni_map_deliver_notifications)
      end
    rescue StandardError => e
      Rails.logger.warn('alumni_map notification enqueue: ' + e.class.name)
    end

    def self.deliver
      return unless enabled?
      pending.order(:next_attempt_at, :id).limit(100).pluck(:id).each do |id|
        deliver_one(id)
      end
    end

    def self.deliver_one(id)
      event = Event.find_by(id: id)
      return unless event
      event.with_lock do
        return if event.notification_id || event.next_attempt_at > Time.current || !enabled?
        account = User.find_by(id: event.user_id)
        unless Access.member?(account)
          event.update!(next_attempt_at: 1.hour.from_now, last_error_class: 'RecipientUnavailable')
          return
        end
        notification = Notification.create!(user_id: event.user_id,
          notification_type: Notification.types[:custom], skip_send_email: true,
          data: {river_app: 'alumni_map', river_text: event.text, river_path: event.path,
            river_icon: 'map-location-dot', message: 'alumni_map', display_username: '', topic_title: event.text}.to_json)
        event.update!(notification_id: notification.id, last_error_class: nil)
      end
    rescue StandardError => e
      # The notification and its event ID roll back together. Defer only the
      # failing row so one recipient cannot starve the rest of the queue.
      Event.transaction do
        failed = Event.lock.find_by(id: id)
        if failed && !failed.notification_id && failed.next_attempt_at <= Time.current
          attempts = [failed.attempts + 1, 16].min
          failed.update!(attempts: attempts, next_attempt_at: [30 * 2**attempts, 3600].min.seconds.from_now,
            last_error_class: e.class.name.to_s.first(100))
        end
      end
      Rails.logger.warn('alumni_map notification ' + id.to_s + ': ' + e.class.name)
    end
  end
end

module ::Jobs
  class DiscourseAlumniMapDeliverNotifications < ::Jobs::Base
    def execute(args)
      DiscourseAlumniMap::Notifications.deliver
      if DiscourseAlumniMap::Notifications.enabled? && DiscourseAlumniMap::Notifications.pending.exists?
        Jobs.enqueue_in(5.seconds, :discourse_alumni_map_deliver_notifications)
      end
    end
  end
end
