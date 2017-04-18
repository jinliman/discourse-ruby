# name: poll
# about: Official poll plugin for Discourse
# version: 0.9
# authors: Vikhyat Korrapati (vikhyat), Régis Hanol (zogstrip)
# url: https://github.com/discourse/discourse/tree/master/plugins/poll

register_asset "stylesheets/common/poll.scss"
register_asset "stylesheets/common/poll-ui-builder.scss"
register_asset "stylesheets/desktop/poll.scss", :desktop
register_asset "stylesheets/mobile/poll.scss", :mobile

PLUGIN_NAME ||= "discourse_poll".freeze

DATA_PREFIX ||= "data-poll-".freeze

after_initialize do

  module ::DiscoursePoll
    DEFAULT_POLL_NAME ||= "poll".freeze
    POLLS_CUSTOM_FIELD ||= "polls".freeze
    VOTES_CUSTOM_FIELD ||= "polls-votes".freeze

    autoload :PollsValidator, "#{Rails.root}/plugins/poll/lib/polls_validator"
    autoload :PollsUpdater, "#{Rails.root}/plugins/poll/lib/polls_updater"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscoursePoll
    end
  end

  class DiscoursePoll::Poll
    class << self

      def vote(post_id, poll_name, options, user)
        DistributedMutex.synchronize("#{PLUGIN_NAME}-#{post_id}") do
          user_id = user.id
          post = Post.find_by(id: post_id)

          # post must not be deleted
          if post.nil? || post.trashed?
            raise StandardError.new I18n.t("poll.post_is_deleted")
          end

          # topic must not be archived
          if post.topic.try(:archived)
            raise StandardError.new I18n.t("poll.topic_must_be_open_to_vote")
          end

          polls = post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD]

          raise StandardError.new I18n.t("poll.no_polls_associated_with_this_post") if polls.blank?

          poll = polls[poll_name]

          raise StandardError.new I18n.t("poll.no_poll_with_this_name", name: poll_name) if poll.blank?
          raise StandardError.new I18n.t("poll.poll_must_be_open_to_vote") if poll["status"] != "open"
          public_poll = (poll["public"] == "true")

          # remove options that aren't available in the poll
          available_options = poll["options"].map { |o| o["id"] }.to_set
          options.select! { |o| available_options.include?(o) }

          raise StandardError.new I18n.t("poll.requires_at_least_1_valid_option") if options.empty?

          poll["voters"] = poll["anonymous_voters"] || 0
          all_options = Hash.new(0)

          post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD] ||= {}
          post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD]["#{user_id}"] ||= {}
          post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD]["#{user_id}"][poll_name] = options

          post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD].each do |_, user_votes|
            next unless votes = user_votes[poll_name]
            votes.each { |option| all_options[option] += 1 }
            poll["voters"] += 1 if (available_options & votes.to_set).size > 0
          end

          poll["options"].each do |option|
            anonymous_votes = option["anonymous_votes"] || 0
            option["votes"] = all_options[option["id"]] + anonymous_votes

            if public_poll
              option["voter_ids"] ||= []

              if options.include?(option["id"])
                option["voter_ids"] << user_id if !option["voter_ids"].include?(user_id)
              else
                option["voter_ids"].delete(user_id)
              end
            end
          end

          post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD] = polls
          post.save_custom_fields(true)

          payload = { post_id: post_id, polls: polls }

          if public_poll
            payload.merge!(user: UserNameSerializer.new(user).serializable_hash)
          end

          MessageBus.publish("/polls/#{post.topic_id}", payload)

          return [poll, options]
        end
      end

      def toggle_status(post_id, poll_name, status, user_id)
        DistributedMutex.synchronize("#{PLUGIN_NAME}-#{post_id}") do
          post = Post.find_by(id: post_id)

          # post must not be deleted
          if post.nil? || post.trashed?
            raise StandardError.new I18n.t("poll.post_is_deleted")
          end

          # topic must not be archived
          if post.topic.try(:archived)
            raise StandardError.new I18n.t("poll.topic_must_be_open_to_toggle_status")
          end

          user = User.find_by(id: user_id)

          # either staff member or OP
          unless user_id == post.user_id || user.try(:staff?)
            raise StandardError.new I18n.t("poll.only_staff_or_op_can_toggle_status")
          end

          polls = post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD]

          raise StandardError.new I18n.t("poll.no_polls_associated_with_this_post") if polls.blank?
          raise StandardError.new I18n.t("poll.no_poll_with_this_name", name: poll_name) if polls[poll_name].blank?

          polls[poll_name]["status"] = status

          post.save_custom_fields(true)

          MessageBus.publish("/polls/#{post.topic_id}", {post_id: post.id, polls: polls })

          polls[poll_name]
        end
      end

      def extract(raw, topic_id, user_id = nil)
        # TODO: we should fix the callback mess so that the cooked version is available
        # in the validators instead of cooking twice
        cooked = PrettyText.cook(raw, topic_id: topic_id, user_id: user_id)
        parsed = Nokogiri::HTML(cooked)

        extracted_polls = []

        # extract polls
        parsed.css("div.poll").each do |p|
          poll = { "options" => [], "voters" => 0 }

          # extract attributes
          p.attributes.values.each do |attribute|
            if attribute.name.start_with?(DATA_PREFIX)
              poll[attribute.name[DATA_PREFIX.length..-1]] = attribute.value
            end
          end

          # extract options
          p.css("li[#{DATA_PREFIX}option-id]").each do |o|
            option_id = o.attributes[DATA_PREFIX + "option-id"].value
            poll["options"] << { "id" => option_id, "html" => o.inner_html, "votes" => 0 }
          end

          # add the poll
          extracted_polls << poll
        end

        extracted_polls
      end
    end
  end

  require_dependency "application_controller"

  class DiscoursePoll::PollsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_filter :ensure_logged_in, except: [:voters]

    def vote
      post_id   = params.require(:post_id)
      poll_name = params.require(:poll_name)
      options   = params.require(:options)

      begin
        poll, options = DiscoursePoll::Poll.vote(post_id, poll_name, options, current_user)
        render json: { poll: poll, vote: options }
      rescue StandardError => e
        render_json_error e.message
      end
    end

    def toggle_status
      post_id   = params.require(:post_id)
      poll_name = params.require(:poll_name)
      status    = params.require(:status)
      user_id   = current_user.id

      begin
        poll = DiscoursePoll::Poll.toggle_status(post_id, poll_name, status, user_id)
        render json: { poll: poll }
      rescue StandardError => e
        render_json_error e.message
      end
    end

    def voters
      post_id = params.require(:post_id)
      poll_name = params.require(:poll_name)

      post = Post.find_by(id: post_id)
      raise Discourse::InvalidParameters.new("post_id is invalid") if !post

      poll = post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD][poll_name]
      raise Discourse::InvalidParameters.new("poll_name is invalid") if !poll

      user_ids = []
      options = poll["options"]

      if poll["type"] != "number"
        options.each do |option|
          if (params[:option_id])
            next unless option["id"] == params[:option_id].to_s
          end

          next unless option["voter_ids"]
          user_ids << option["voter_ids"].slice((params[:offset].to_i || 0)  * 25, 25)
        end

        user_ids.flatten!
        user_ids.uniq!

        poll_votes = post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD]

        result = {}

        User.where(id: user_ids).map do |user|
          user_hash = UserNameSerializer.new(user).serializable_hash

          poll_votes[user.id.to_s][poll_name].each do |option_id|
            if (params[:option_id])
              next unless option_id == params[:option_id].to_s
            end

            result[option_id] ||= []
            result[option_id] << user_hash
          end
        end
      else
        user_ids = options.map { |option| option["voter_ids"] }.sort!
        user_ids.flatten!
        user_ids.uniq!
        user_ids = user_ids.slice((params[:offset].to_i || 0) * 25, 25)

        result = []

        users = User.where(id: user_ids).map do |user|
          result << UserNameSerializer.new(user).serializable_hash
        end
      end

      render json: { poll_name => result }
    end
  end

  DiscoursePoll::Engine.routes.draw do
    put "/vote" => "polls#vote"
    put "/toggle_status" => "polls#toggle_status"
    get "/voters" => 'polls#voters'
  end

  Discourse::Application.routes.append do
    mount ::DiscoursePoll::Engine, at: "/polls"
  end

  Post.class_eval do
    attr_accessor :polls

    after_save do
      next if self.polls.blank? || !self.polls.is_a?(Hash)

      post = self
      polls = self.polls

      DistributedMutex.synchronize("#{PLUGIN_NAME}-#{post.id}") do
        post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD] = polls
        post.save_custom_fields(true)
      end
    end
  end

  validate(:post, :validate_polls) do |force=nil|
    return if !SiteSetting.poll_enabled? && (self.user && !self.user.staff?)

    # only care when raw has changed!
    return unless self.raw_changed? || force

    validator = DiscoursePoll::PollsValidator.new(self)
    return unless (polls = validator.validate_polls)

    # are we updating a post?
    if self.id.present?
      DistributedMutex.synchronize("#{PLUGIN_NAME}-#{self.id}") do
        DiscoursePoll::PollsUpdater.update(self, polls)
      end
    else
      self.polls = polls
    end

    true
  end

  NewPostManager.add_handler(1) do |manager|
    post = Post.new(raw: manager.args[:raw])

    if !DiscoursePoll::PollsValidator.new(post).validate_polls
      result = NewPostResult.new(:poll, false)

      post.errors.full_messages.each do |message|
        result.errors[:base] << message
      end

      result
    else
      manager.args["is_poll"] = true
      nil
    end
  end

  on(:approved_post) do |queued_post, created_post|
    if queued_post.post_options["is_poll"]
      created_post.validate_polls(true)
    end
  end

  Post.register_custom_field_type(DiscoursePoll::POLLS_CUSTOM_FIELD, :json)
  Post.register_custom_field_type(DiscoursePoll::VOTES_CUSTOM_FIELD, :json)

  TopicView.add_post_custom_fields_whitelister do |user|
    user ? [DiscoursePoll::POLLS_CUSTOM_FIELD, DiscoursePoll::VOTES_CUSTOM_FIELD] : [DiscoursePoll::POLLS_CUSTOM_FIELD]
  end

  on(:reduce_cooked) do |fragment, post|
    if post.nil? || post.trashed?
      fragment.css(".poll, [data-poll-name]").each(&:remove)
    else
      post_url = "#{Discourse.base_url}#{post.url}"
      fragment.css(".poll, [data-poll-name]").each do |poll|
        poll.replace "<p><a href='#{post_url}'>#{I18n.t("poll.email.link_to_poll")}</a></p>"
      end
    end
  end

  # tells the front-end we have a poll for that post
  on(:post_created) do |post|
    next if post.is_first_post? || post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD].blank?
    MessageBus.publish("/polls/#{post.topic_id}", {
                         post_id: post.id,
                         polls: post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD]})
  end

  add_to_serializer(:post, :polls, false) do
    polls = post_custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD].dup

    polls.each do |_, poll|
      poll["options"].each do |option|
        option.delete("voter_ids")
      end
    end
  end

  add_to_serializer(:post, :include_polls?) { post_custom_fields.present? && post_custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD].present? }

  add_to_serializer(:post, :polls_votes, false) do
    post_custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD]["#{scope.user.id}"]
  end

  add_to_serializer(:post, :include_polls_votes?) do
    return unless scope.user
    return unless post_custom_fields.present?
    return unless post_custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD].present?
    post_custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD].has_key?("#{scope.user.id}")
  end
end
