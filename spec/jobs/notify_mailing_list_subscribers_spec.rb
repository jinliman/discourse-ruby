require "rails_helper"

describe Jobs::NotifyMailingListSubscribers do

  let(:mailing_list_user) { Fabricate(:user) }

  before { mailing_list_user.user_option.update(mailing_list_mode: true, mailing_list_mode_frequency: 1) }

  let(:user) { Fabricate(:user) }
  let(:post) { Fabricate(:post, user: user) }

  shared_examples "no emails" do
    it "doesn't send any emails" do
      UserNotifications.expects(:mailing_list_notify).with(mailing_list_user, post).never
      Jobs::NotifyMailingListSubscribers.new.execute(post_id: post.id)
    end
  end

  shared_examples "one email" do
    it "sends the email" do
      UserNotifications.expects(:mailing_list_notify).with(mailing_list_user, post).once
      Jobs::NotifyMailingListSubscribers.new.execute(post_id: post.id)
    end
  end

  context "when mailing list mode is globally disabled" do
    before { SiteSetting.disable_mailing_list_mode = true }
    include_examples "no emails"
  end

  context "when mailing list mode is globally enabled" do
    before { SiteSetting.disable_mailing_list_mode = false }

    context "with an invalid post_id" do
      it "throws an error" do
        expect { Jobs::NotifyMailingListSubscribers.new.execute(post_id: -1) }.to raise_error(Discourse::InvalidParameters)
      end
    end

    context "with a deleted post" do
      before { post.update(deleted_at: Time.now) }
      include_examples "no emails"
    end

    context "with a user_deleted post" do
      before { post.update(user_deleted: true) }
      include_examples "no emails"
    end

    context "with a deleted topic" do
      before { post.topic.update(deleted_at: Time.now) }
      include_examples "no emails"
    end

    context "with a valid post from another user" do

      context "to an inactive user" do
        before { mailing_list_user.update(active: false) }
        include_examples "no emails"
      end

      context "to a blocked user" do
        before { mailing_list_user.update(blocked: true) }
        include_examples "no emails"
      end

      context "to a suspended user" do
        before { mailing_list_user.update(suspended_till: 1.day.from_now) }
        include_examples "no emails"
      end

      context "to an anonymous user" do
        let(:mailing_list_user) { Fabricate(:anonymous) }
        include_examples "no emails"
      end

      context "to an user who has disabled mailing list mode" do
        before { mailing_list_user.user_option.update(mailing_list_mode: false) }
        include_examples "no emails"
      end

      context "to an user who has frequency set to 'daily'" do
        before { mailing_list_user.user_option.update(mailing_list_mode_frequency: 0) }
        include_examples "no emails"
      end

      context "to an user who has frequency set to 'always'" do
        before { mailing_list_user.user_option.update(mailing_list_mode_frequency: 1) }
        include_examples "one email"
      end

      context "to an user who has frequency set to 'no echo'" do
        before { mailing_list_user.user_option.update(mailing_list_mode_frequency: 2) }
        include_examples "one email"
      end

      context "from a muted user" do
        before { MutedUser.create(user: mailing_list_user, muted_user: user) }
        include_examples "no emails"
      end

      context "from a muted topic" do
        before { TopicUser.create(user: mailing_list_user, topic: post.topic, notification_level: TopicUser.notification_levels[:muted]) }
        include_examples "no emails"
      end

      context "from a muted category" do
        before { CategoryUser.create(user: mailing_list_user, category: post.topic.category, notification_level: CategoryUser.notification_levels[:muted]) }
        include_examples "no emails"
      end

      context "max emails per day was reached" do
        before { SiteSetting.max_emails_per_day_per_user = 2 }

        it "doesn't send any emails" do
          (SiteSetting.max_emails_per_day_per_user + 1).times {
            mailing_list_user.email_logs.create(email_type: 'foobar', to_address: mailing_list_user.email)
          }

          Jobs::NotifyMailingListSubscribers.new.execute(post_id: post.id)
          UserNotifications.expects(:mailing_list_notify).with(mailing_list_user, post).never

          expect(EmailLog.where(user: mailing_list_user, skipped: true).count).to eq(1)
        end
      end

      context "bounce score was reached" do

        it "doesn't send any emails" do
          mailing_list_user.user_stat.update(bounce_score: SiteSetting.bounce_score_threshold + 1)

          Jobs::NotifyMailingListSubscribers.new.execute(post_id: post.id)
          UserNotifications.expects(:mailing_list_notify).with(mailing_list_user, post).never

          expect(EmailLog.where(user: mailing_list_user, skipped: true).count).to eq(1)
        end

      end

    end

    context "with a valid post from same user" do
      let(:post) { Fabricate(:post, user: mailing_list_user) }

      context "to an user who has frequency set to 'daily'" do
        before { mailing_list_user.user_option.update(mailing_list_mode_frequency: 0) }
        include_examples "no emails"
      end

      context "to an user who has frequency set to 'always'" do
        before { mailing_list_user.user_option.update(mailing_list_mode_frequency: 1) }
        include_examples "one email"
      end

      context "to an user who has frequency set to 'no echo'" do
        before { mailing_list_user.user_option.update(mailing_list_mode_frequency: 2) }
        include_examples "no emails"
      end
    end

  end

end
