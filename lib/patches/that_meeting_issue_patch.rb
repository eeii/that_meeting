require_dependency 'issue'

module Patches
    module ThatMeetingIssuePatch

        def self.included(base)
            base.send(:include, InstanceMethods)
            base.class_eval do
                unloadable

                has_one :meeting, :class_name => 'IssueMeeting', :autosave => true, :dependent => :destroy

                has_many :acceptances, lambda {
                    where(:property => 'attendee').order("#{JournalDetail.table_name}.id DESC")
                }, :through => :journals, :source => :details

                delegate :start_time, :start_time=,
                         :end_time,   :end_time=,
                         :recurrence, :recurrence=, :to => :meeting, :allow_nil => true

                validate :validate_meeting, :if => Proc.new { |issue| issue.meeting? }
                validate :validate_parent_meeting

                safe_attributes :start_time, :end_time, :recurrence, :if => lambda { |issue, user|
                    issue.new_record? || issue.attributes_editable?(user)
                }

                alias_method_chain :safe_attribute_names,        :meeting
                alias_method_chain :required_attribute_names,    :meeting
                alias_method_chain :journalized_attribute_names, :meeting
                alias_method_chain :each_notification,           :meeting
            end
        end

        module InstanceMethods

            def meeting?
                Setting.plugin_that_meeting['tracker_ids'].is_a?(Array) && Setting.plugin_that_meeting['tracker_ids'].include?(tracker_id.to_s)
            end

            def meeting
                issue_meeting = super
                if issue_meeting.nil?
                    issue_meeting = build_meeting if meeting?
                elsif !meeting?
                    issue_meeting = self.meeting = nil
                end
                issue_meeting
            end

            def formatted_start_time
                start_time.strftime('%H:%M') if meeting? && start_time
            end

            def formatted_end_time
                end_time.strftime('%H:%M') if meeting? && end_time
            end

            def safe_attribute_names_with_meeting(user = nil)
                attribute_names = safe_attribute_names_without_meeting(user)
                if meeting?
                    attribute_names << 'assigned_to_id' unless attribute_names.include?('assigned_to_id')
                    attribute_names << 'start_date' unless attribute_names.include?('start_date')
                end
                attribute_names
            end

            def required_attribute_names_with_meeting(user = nil)
                required_attributes = required_attribute_names_without_meeting(user)
                if meeting?
                    required_attributes << 'assigned_to_id' unless required_attributes.include?('assigned_to_id')
                    required_attributes << 'start_date' unless required_attributes.include?('start_date')
                end
                required_attributes
            end

            def journalized_attribute_names_with_meeting
                attribute_names = journalized_attribute_names_without_meeting
                attribute_names += %w(start_time end_time recurrence) if meeting?
                attribute_names
            end

            def each_notification_with_meeting(users, &block)
                if meeting? && users.any?
                    attendees, rest = users.partition{ |user| watched_by?(user) }
                    attendees.each do |attendee|
                        yield([ attendee ])
                    end
                    each_notification_without_meeting(rest, &block)
                else
                    each_notification_without_meeting(users, &block)
                end
            end

        private

            def validate_meeting
                meeting.errors.full_messages.each do |message|
                    errors.add(:base, message)
                end unless meeting.valid?
                meeting.recurrence.errors.full_messages.each do |message|
                    errors.add(:base, message)
                end unless meeting.recurrence.valid?
                if start_date && meeting.recurrence.until && start_date > meeting.recurrence.until
                    errors.add(:base, l(:recurrence_until) + ' ' + l('activerecord.errors.messages.greater_than_start_date'))
                end
            end

            def validate_parent_meeting
                p = instance_variable_defined?(:@parent_issue) ? @parent_issue : parent
                if p && Setting.parent_issue_dates == 'derived'
                    errors.add(:parent_issue_id, :invalid) if p.meeting?
                end
            end

        end

    end
end
