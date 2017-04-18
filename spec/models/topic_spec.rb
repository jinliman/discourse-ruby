# encoding: utf-8

require 'rails_helper'
require_dependency 'post_destroyer'

describe Topic do
  let(:now) { Time.zone.local(2013,11,20,8,0) }
  let(:user) { Fabricate(:user) }

  context 'validations' do
    let(:topic) { Fabricate.build(:topic) }

    context "#title" do
      it { is_expected.to validate_presence_of :title }

      describe 'censored pattern' do
        describe 'when title matches censored pattern' do
          it 'should not be valid' do
            SiteSetting.censored_pattern = 'orange.*'

            topic.title = 'I have orangEjuice orange monkey orange stuff'

            expect(topic).to_not be_valid

            expect(topic.errors.full_messages.first).to include(I18n.t(
              'errors.messages.matches_censored_pattern', censored_words: 'orangejuice orange monkey orange stuff'
            ))
          end
        end
      end

      describe 'censored words' do
        describe 'when title contains censored words' do
          it 'should not be valid' do
            SiteSetting.censored_words = 'pineapple|pen'

            topic.title = 'pen PinEapple apple pen '

            expect(topic).to_not be_valid

            expect(topic.errors.full_messages.first).to include(I18n.t(
              'errors.messages.contains_censored_words', censored_words: 'pen, pineapple'
            ))
          end
        end

        describe 'when title does not contain censored words' do
          it 'should be valid' do
            topic.title = 'The cake is a lie'

            expect(topic).to be_valid
          end
        end

        describe 'escape special characters in censored words' do
          before do
            SiteSetting.censored_words = 'co(onut|coconut|a**le'
          end

          it 'should not valid' do
            topic.title = "I have a co(onut a**le"

            expect(topic.valid?).to eq(false)

            expect(topic.errors.full_messages.first).to include(I18n.t(
              'errors.messages.contains_censored_words',
              censored_words: 'co(onut, a**le'
            ))
          end
        end
      end
    end
  end

  it { is_expected.to rate_limit }

  context '#visible_post_types' do
    let(:types) { Post.types }

    it "returns the appropriate types for anonymous users" do
      post_types = Topic.visible_post_types

      expect(post_types).to include(types[:regular])
      expect(post_types).to include(types[:moderator_action])
      expect(post_types).to include(types[:small_action])
      expect(post_types).to_not include(types[:whisper])
    end

    it "returns the appropriate types for regular users" do
      post_types = Topic.visible_post_types(Fabricate.build(:user))

      expect(post_types).to include(types[:regular])
      expect(post_types).to include(types[:moderator_action])
      expect(post_types).to include(types[:small_action])
      expect(post_types).to_not include(types[:whisper])
    end

    it "returns the appropriate types for staff users" do
      post_types = Topic.visible_post_types(Fabricate.build(:moderator))

      expect(post_types).to include(types[:regular])
      expect(post_types).to include(types[:moderator_action])
      expect(post_types).to include(types[:small_action])
      expect(post_types).to include(types[:whisper])
    end
  end

  context 'slug' do
    let(:title) { "hello world topic" }
    let(:slug) { "hello-world-topic" }
    context 'encoded generator' do
      before { SiteSetting.slug_generation_method = 'encoded' }
      after { SiteSetting.slug_generation_method = 'ascii' }

      it "returns a Slug for a title" do
        Slug.expects(:for).with(title).returns(slug)
        expect(Fabricate.build(:topic, title: title).slug).to eq(slug)
      end

      context 'for cjk characters' do
        let(:title) { "熱帶風暴畫眉" }
        let(:slug) { "熱帶風暴畫眉" }
        it "returns encoded Slug for a title" do
          Slug.expects(:for).with(title).returns(slug)
          expect(Fabricate.build(:topic, title: title).slug).to eq(slug)
        end
      end

      context 'for numbers' do
        let(:title) { "123456789" }
        let(:slug) { "topic" }
        it 'generates default slug' do
          Slug.expects(:for).with(title).returns("topic")
          expect(Fabricate.build(:topic, title: title).slug).to eq("topic")
        end
      end
    end

    context 'none generator' do
      before { SiteSetting.slug_generation_method = 'none' }
      after { SiteSetting.slug_generation_method = 'ascii' }
      let(:title) { "熱帶風暴畫眉" }
      let(:slug) { "topic" }

      it "returns a Slug for a title" do
        Slug.expects(:for).with(title).returns('topic')
        expect(Fabricate.build(:topic, title: title).slug).to eq(slug)
      end
    end

    context '#ascii_generator' do
      before { SiteSetting.slug_generation_method = 'ascii' }
      it "returns a Slug for a title" do
        Slug.expects(:for).with(title).returns(slug)
        expect(Fabricate.build(:topic, title: title).slug).to eq(slug)
      end

      context 'for cjk characters' do
        let(:title) { "熱帶風暴畫眉" }
        let(:slug) { 'topic' }
        it "returns 'topic' when the slug is empty (say, non-latin characters)" do
          Slug.expects(:for).with(title).returns("topic")
          expect(Fabricate.build(:topic, title: title).slug).to eq("topic")
        end
      end
    end
  end

  context "updating a title to be shorter" do
    let!(:topic) { Fabricate(:topic) }

    it "doesn't update it to be shorter due to cleaning using TextCleaner" do
      topic.title = 'unread    glitch'
      expect(topic.save).to eq(false)
    end
  end

  context 'private message title' do
    before do
      SiteSetting.stubs(:min_topic_title_length).returns(15)
      SiteSetting.stubs(:min_private_message_title_length).returns(3)
    end

    it 'allows shorter titles' do
      pm = Fabricate.build(:private_message_topic, title: 'a' * SiteSetting.min_private_message_title_length)
      expect(pm).to be_valid
    end

    it 'but not too short' do
      pm = Fabricate.build(:private_message_topic, title: 'a')
      expect(pm).to_not be_valid
    end
  end

  context 'admin topic title' do
    let(:admin) { Fabricate(:admin) }

    it 'allows really short titles' do
      pm = Fabricate.build(:private_message_topic, user: admin, title: 'a')
      expect(pm).to be_valid
    end

    it 'but not blank' do
      pm = Fabricate.build(:private_message_topic, title: '')
      expect(pm).to_not be_valid
    end
  end

  context 'topic title uniqueness' do

    let!(:topic) { Fabricate(:topic) }
    let(:new_topic) { Fabricate.build(:topic, title: topic.title) }

    context "when duplicates aren't allowed" do
      before do
        SiteSetting.expects(:allow_duplicate_topic_titles?).returns(false)
      end

      it "won't allow another topic to be created with the same name" do
        expect(new_topic).not_to be_valid
      end

      it "won't allow another topic with an upper case title to be created" do
        new_topic.title = new_topic.title.upcase
        expect(new_topic).not_to be_valid
      end

      it "allows it when the topic is deleted" do
        topic.destroy
        expect(new_topic).to be_valid
      end

      it "allows a private message to be created with the same topic" do
        new_topic.archetype = Archetype.private_message
        expect(new_topic).to be_valid
      end
    end

    context "when duplicates are allowed" do
      before do
        SiteSetting.expects(:allow_duplicate_topic_titles?).returns(true)
      end

      it "will allow another topic to be created with the same name" do
        expect(new_topic).to be_valid
      end
    end

  end

  context 'html in title' do

    def build_topic_with_title(title)
      build(:topic, title: title).tap{ |t| t.valid? }
    end

    let(:topic_bold) { build_topic_with_title("Topic with <b>bold</b> text in its title" ) }
    let(:topic_image) { build_topic_with_title("Topic with <img src='something'> image in its title" ) }
    let(:topic_script) { build_topic_with_title("Topic with <script>alert('title')</script> script in its title" ) }

    it "escapes script contents" do
      expect(topic_script.fancy_title).to eq("Topic with &lt;script&gt;alert(&lsquo;title&rsquo;)&lt;/script&gt; script in its title")
    end

    it "escapes bold contents" do
      expect(topic_bold.fancy_title).to eq("Topic with &lt;b&gt;bold&lt;/b&gt; text in its title")
    end

    it "escapes image contents" do
      expect(topic_image.fancy_title).to eq("Topic with &lt;img src=&lsquo;something&rsquo;&gt; image in its title")
    end

  end

  context 'fancy title' do
    let(:topic) { Fabricate.build(:topic, title: "\"this topic\" -- has ``fancy stuff''" ) }

    context 'title_fancy_entities disabled' do
      before do
        SiteSetting.title_fancy_entities = false
      end

      it "doesn't add entities to the title" do
        expect(topic.fancy_title).to eq("&quot;this topic&quot; -- has ``fancy stuff&#39;&#39;")
      end
    end

    context 'title_fancy_entities enabled' do
      before do
        SiteSetting.title_fancy_entities = true
      end

      it "converts the title to have fancy entities and updates" do
        expect(topic.fancy_title).to eq("&ldquo;this topic&rdquo; &ndash; has &ldquo;fancy stuff&rdquo;")
        topic.title = "this is my test hello world... yay"
        topic.user.save!
        topic.save!
        topic.reload
        expect(topic.fancy_title).to eq("This is my test hello world&hellip; yay")

        topic.title = "I made a change to the title"
        topic.save!

        topic.reload
        expect(topic.fancy_title).to eq("I made a change to the title")

        # another edge case
        topic.title = "this is another edge case"
        expect(topic.fancy_title).to eq("this is another edge case")
      end
    end
  end

  context 'category validation' do
    context 'allow_uncategorized_topics is false' do
      before do
        SiteSetting.stubs(:allow_uncategorized_topics).returns(false)
      end

      it "does not allow nil category" do
        topic = Fabricate.build(:topic, category: nil)
        expect(topic).not_to be_valid
        expect(topic.errors[:category_id]).to be_present
      end

      it "allows PMs" do
        topic = Fabricate.build(:topic, category: nil, archetype: Archetype.private_message)
        expect(topic).to be_valid
      end

      it 'passes for topics with a category' do
        expect(Fabricate.build(:topic, category: Fabricate(:category))).to be_valid
      end
    end

    context 'allow_uncategorized_topics is true' do
      before do
        SiteSetting.stubs(:allow_uncategorized_topics).returns(true)
      end

      it "passes for topics with nil category" do
        expect(Fabricate.build(:topic, category: nil)).to be_valid
      end

      it 'passes for topics with a category' do
        expect(Fabricate.build(:topic, category: Fabricate(:category))).to be_valid
      end
    end
  end


  context 'similar_to' do

    it 'returns blank with nil params' do
      expect(Topic.similar_to(nil, nil)).to be_blank
    end

    context "with a category definition" do
      let!(:category) { Fabricate(:category) }

      it "excludes the category definition topic from similar_to" do
        expect(Topic.similar_to('category definition for', "no body")).to be_blank
      end
    end

    context 'with a similar topic' do
      let!(:topic) {
        SearchIndexer.enable
        post = create_post(title: "Evil trout is the dude who posted this topic")
        post.topic
      }

      it 'returns the similar topic if the title is similar' do
        expect(Topic.similar_to("has evil trout made any topics?", "i am wondering has evil trout made any topics?")).to eq([topic])
      end

      context "secure categories" do
        let(:category) { Fabricate(:category, read_restricted: true) }

        before do
          topic.category = category
          topic.save
        end

        it "doesn't return topics from private categories" do
          expect(Topic.similar_to("has evil trout made any topics?", "i am wondering has evil trout made any topics?", user)).to be_blank
        end

        it "should return the cat since the user can see it" do
          Guardian.any_instance.expects(:secure_category_ids).returns([category.id])
          expect(Topic.similar_to("has evil trout made any topics?", "i am wondering has evil trout made any topics?", user)).to include(topic)
        end
      end

    end

  end

  context 'post_numbers' do
    let!(:topic) { Fabricate(:topic) }
    let!(:p1) { Fabricate(:post, topic: topic, user: topic.user) }
    let!(:p2) { Fabricate(:post, topic: topic, user: topic.user) }
    let!(:p3) { Fabricate(:post, topic: topic, user: topic.user) }

    it "returns the post numbers of the topic" do
      expect(topic.post_numbers).to eq([1, 2, 3])
      p2.destroy
      topic.reload
      expect(topic.post_numbers).to eq([1, 3])
    end

  end


  context 'private message' do
    let(:coding_horror) { User.find_by(username: "CodingHorror") }
    let(:evil_trout) { Fabricate(:evil_trout) }
    let(:topic) { Fabricate(:private_message_topic) }

    it "should integrate correctly" do
      expect(Guardian.new(topic.user).can_see?(topic)).to eq(true)
      expect(Guardian.new.can_see?(topic)).to eq(false)
      expect(Guardian.new(evil_trout).can_see?(topic)).to eq(false)
      expect(Guardian.new(coding_horror).can_see?(topic)).to eq(true)
      expect(TopicQuery.new(evil_trout).list_latest.topics).not_to include(topic)

      # invites
      expect(topic.invite(topic.user, 'duhhhhh')).to eq(false)
    end

    context 'invite' do

      context 'existing user' do
        let(:walter) { Fabricate(:walter_white) }

        context 'by group name' do

          it 'can add admin to allowed groups' do
            admins = Group[:admins]
            admins.alias_level = Group::ALIAS_LEVELS[:everyone]
            admins.save

            expect(topic.invite_group(topic.user, admins)).to eq(true)

            expect(topic.allowed_groups.include?(admins)).to eq(true)

            expect(topic.remove_allowed_group(topic.user, 'admins')).to eq(true)
            topic.reload

            expect(topic.allowed_groups.include?(admins)).to eq(false)
          end

        end

        context 'by username' do

          it 'adds and removes walter to the allowed users' do
            expect(topic.invite(topic.user, walter.username)).to eq(true)
            expect(topic.allowed_users.include?(walter)).to eq(true)

            expect(topic.remove_allowed_user(topic.user, walter.username)).to eq(true)
            topic.reload
            expect(topic.allowed_users.include?(walter)).to eq(false)
          end

          it 'creates a notification' do
            expect { topic.invite(topic.user, walter.username) }.to change(Notification, :count)
          end

          it 'creates a small action post' do
            expect { topic.invite(topic.user, walter.username) }.to change(Post, :count)
            expect { topic.remove_allowed_user(topic.user, walter.username) }.to change(Post, :count)
          end
        end

        context 'by email' do

          it 'adds user correctly' do
            expect {
              expect(topic.invite(topic.user, walter.email)).to eq(true)
            }.to change(Notification, :count)
            expect(topic.allowed_users.include?(walter)).to eq(true)
          end

        end
      end

    end

    context "user actions" do
      let(:actions) { topic.user.user_actions }

      it "should set up actions correctly" do
        UserActionCreator.enable

        expect(actions.map{|a| a.action_type}).not_to include(UserAction::NEW_TOPIC)
        expect(actions.map{|a| a.action_type}).to include(UserAction::NEW_PRIVATE_MESSAGE)
        expect(coding_horror.user_actions.map{|a| a.action_type}).to include(UserAction::GOT_PRIVATE_MESSAGE)
      end

    end

  end

  context 'rate limits' do

    it "rate limits topic invitations" do
      SiteSetting.stubs(:max_topic_invitations_per_day).returns(2)
      RateLimiter.stubs(:disabled?).returns(false)
      RateLimiter.clear_all!

      start = Time.now.tomorrow.beginning_of_day
      freeze_time(start)

      user = Fabricate(:user)
      trust_level_2 = Fabricate(:user, trust_level: 2)
      topic = Fabricate(:topic, user: trust_level_2)

      freeze_time(start + 10.minutes)
      topic.invite(topic.user, user.username)

      freeze_time(start + 20.minutes)
      topic.invite(topic.user, "walter@white.com")

      freeze_time(start + 30.minutes)

      expect {
        topic.invite(topic.user, "user@example.com")
      }.to raise_error(RateLimiter::LimitExceeded)
    end

  end

  context 'bumping topics' do

    before do
      @topic = Fabricate(:topic, bumped_at: 1.year.ago)
    end

    it 'updates the bumped_at field when a new post is made' do
      expect(@topic.bumped_at).to be_present
      expect {
        create_post(topic: @topic, user: @topic.user)
        @topic.reload
      }.to change(@topic, :bumped_at)
    end

    context 'editing posts' do
      before do
        @earlier_post = Fabricate(:post, topic: @topic, user: @topic.user)
        @last_post = Fabricate(:post, topic: @topic, user: @topic.user)
        @topic.reload
      end

      it "doesn't bump the topic on an edit to the last post that doesn't result in a new version" do
        expect {
          SiteSetting.expects(:editing_grace_period).returns(5.minutes)
          @last_post.revise(@last_post.user, { raw: 'updated contents' }, revised_at: @last_post.created_at + 10.seconds)
          @topic.reload
        }.not_to change(@topic, :bumped_at)
      end

      it "bumps the topic when a new version is made of the last post" do
        expect {
          @last_post.revise(Fabricate(:moderator), { raw: 'updated contents' })
          @topic.reload
        }.to change(@topic, :bumped_at)
      end

      it "doesn't bump the topic when a post that isn't the last post receives a new version" do
        expect {
          @earlier_post.revise(Fabricate(:moderator), { raw: 'updated contents' })
          @topic.reload
        }.not_to change(@topic, :bumped_at)
      end

      it "doesn't bump the topic when a post have invalid topic title while edit" do
        expect {
          @last_post.revise(Fabricate(:moderator), { title: 'invalid title' })
          @topic.reload
        }.not_to change(@topic, :bumped_at)
      end
    end
  end

  context 'moderator posts' do
    let(:moderator) { Fabricate(:moderator) }
    let(:topic) { Fabricate(:topic) }

    it 'creates a moderator post' do
      mod_post = topic.add_moderator_post(
        moderator,
        "Moderator did something. http://discourse.org",
        post_number: 999
      )

      expect(mod_post).to be_present
      expect(mod_post.post_type).to eq(Post.types[:moderator_action])
      expect(mod_post.post_number).to eq(999)
      expect(mod_post.sort_order).to eq(999)
      expect(topic.topic_links.count).to eq(1)
      expect(topic.reload.moderator_posts_count).to eq(1)
    end

    context "when moderator post fails to be created" do
      before do
        user.toggle!(:blocked)
      end

      it "should not increment moderator_posts_count" do
        expect(topic.moderator_posts_count).to eq(0)

        topic.add_moderator_post(user, "winter is never coming")

        expect(topic.moderator_posts_count).to eq(0)
      end
    end
  end


  context 'update_status' do
    before do
      @topic = Fabricate(:topic, bumped_at: 1.hour.ago)
      @topic.reload
      @original_bumped_at = @topic.bumped_at.to_f
      @user = @topic.user
      @user.admin = true
    end

    context 'visibility' do
      context 'disable' do
        before do
          @topic.update_status('visible', false, @user)
          @topic.reload
        end

        it 'should not be visible and have correct counts' do
          expect(@topic).not_to be_visible
          expect(@topic.moderator_posts_count).to eq(1)
          expect(@topic.bumped_at.to_f).to eq(@original_bumped_at)
        end
      end

      context 'enable' do
        before do
          @topic.update_attribute :visible, false
          @topic.update_status('visible', true, @user)
          @topic.reload
        end

        it 'should be visible with correct counts' do
          expect(@topic).to be_visible
          expect(@topic.moderator_posts_count).to eq(1)
          expect(@topic.bumped_at.to_f).to eq(@original_bumped_at)
        end
      end
    end

    context 'pinned' do
      context 'disable' do
        before do
          @topic.update_status('pinned', false, @user)
          @topic.reload
        end

        it "doesn't have a pinned_at but has correct dates" do
          expect(@topic.pinned_at).to be_blank
          expect(@topic.moderator_posts_count).to eq(1)
          expect(@topic.bumped_at.to_f).to eq(@original_bumped_at)
        end
      end

      context 'enable' do
        before do
          @topic.update_attribute :pinned_at, nil
          @topic.update_status('pinned', true, @user)
          @topic.reload
        end

        it 'should enable correctly' do
          expect(@topic.pinned_at).to be_present
          expect(@topic.bumped_at.to_f).to eq(@original_bumped_at)
          expect(@topic.moderator_posts_count).to eq(1)
        end

      end
    end

    context 'archived' do
      context 'disable' do
        before do
          @archived_topic = Fabricate(:topic, archived: true, bumped_at: 1.hour.ago)
          @original_bumped_at = @archived_topic.bumped_at.to_f
          @archived_topic.update_status('archived', false, @user)
          @archived_topic.reload
        end

        it 'should archive correctly' do
          expect(@archived_topic).not_to be_archived
          expect(@archived_topic.bumped_at.to_f).to be_within(0.1).of(@original_bumped_at)
          expect(@archived_topic.moderator_posts_count).to eq(1)
        end
      end

      context 'enable' do
        before do
          @topic.update_attribute :archived, false
          @topic.update_status('archived', true, @user)
          @topic.reload
        end

        it 'should be archived' do
          expect(@topic).to be_archived
          expect(@topic.moderator_posts_count).to eq(1)
          expect(@topic.bumped_at.to_f).to eq(@original_bumped_at)
        end

      end
    end

    shared_examples_for 'a status that closes a topic' do
      context 'disable' do
        before do
          @closed_topic = Fabricate(:topic, closed: true, bumped_at: 1.hour.ago)
          @original_bumped_at = @closed_topic.bumped_at.to_f
          @closed_topic.update_status(status, false, @user)
          @closed_topic.reload
        end

        it 'should not be pinned' do
          expect(@closed_topic).not_to be_closed
          expect(@closed_topic.moderator_posts_count).to eq(1)
          expect(@closed_topic.bumped_at.to_f).not_to eq(@original_bumped_at)
        end

      end

      context 'enable' do
        before do
          @topic.update_attribute :closed, false
          @topic.update_status(status, true, @user)
          @topic.reload
        end

        it 'should be closed' do
          expect(@topic).to be_closed
          expect(@topic.bumped_at.to_f).to eq(@original_bumped_at)
          expect(@topic.moderator_posts_count).to eq(1)
          expect(@topic.topic_status_updates.first).to eq(nil)
        end
      end
    end

    context 'closed' do
      let(:status) { 'closed' }
      it_should_behave_like 'a status that closes a topic'
    end

    context 'autoclosed' do
      let(:status) { 'autoclosed' }
      it_should_behave_like 'a status that closes a topic'

      context 'topic was set to close when it was created' do
        it 'puts the autoclose duration in the moderator post' do
          freeze_time(Time.new(2000,1,1))
          @topic.created_at = 3.days.ago
          @topic.update_status(status, true, @user)
          expect(@topic.posts.last.raw).to include "closed after 3 days"
        end
      end

      context 'topic was set to close after it was created' do
        it 'puts the autoclose duration in the moderator post' do
          freeze_time(Time.new(2000,1,1))

          @topic.created_at = 7.days.ago

          freeze_time(2.days.ago)

          @topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 48)
          @topic.save!

          freeze_time(2.days.from_now)

          @topic.update_status(status, true, @user)
          expect(@topic.posts.last.raw).to include "closed after 2 days"
        end
      end
    end
  end

  describe "banner" do

    let(:topic) { Fabricate(:topic) }
    let(:user) { topic.user }
    let(:banner) { { html: "<p>BANNER</p>", url: topic.url, key: topic.id } }

    before { topic.stubs(:banner).returns(banner) }

    describe "make_banner!" do

      it "changes the topic archetype to 'banner'" do
        messages = MessageBus.track_publish do
          topic.make_banner!(user)
          expect(topic.archetype).to eq(Archetype.banner)
        end

        channels = messages.map(&:channel)
        expect(channels).to include('/site/banner')
        expect(channels).to include('/distributed_hash')
      end

      it "ensures only one banner topic at all time" do
        _banner_topic = Fabricate(:banner_topic)
        expect(Topic.where(archetype: Archetype.banner).count).to eq(1)

        topic.make_banner!(user)
        expect(Topic.where(archetype: Archetype.banner).count).to eq(1)
      end

      it "removes any dismissed banner keys" do
        user.user_profile.update_column(:dismissed_banner_key, topic.id)

        topic.make_banner!(user)
        user.user_profile.reload
        expect(user.user_profile.dismissed_banner_key).to be_nil
      end

    end

    describe "remove_banner!" do

      it "resets the topic archetype" do
        topic.expects(:add_moderator_post)
        MessageBus.expects(:publish).with("/site/banner", nil)
        topic.remove_banner!(user)
        expect(topic.archetype).to eq(Archetype.default)
      end

    end


  end

  context 'last_poster info' do

    before do
      @post = create_post
      @user = @post.user
      @topic = @post.topic
    end

    it 'initially has the last_post_user_id of the OP' do
      expect(@topic.last_post_user_id).to eq(@user.id)
    end

    context 'after a second post' do
      before do
        @second_user = Fabricate(:coding_horror)
        @new_post = create_post(topic: @topic, user: @second_user)
        @topic.reload
      end

      it 'updates the last_post_user_id to the second_user' do
        expect(@topic.last_post_user_id).to eq(@second_user.id)
        expect(@topic.last_posted_at.to_i).to eq(@new_post.created_at.to_i)
        topic_user = @second_user.topic_users.find_by(topic_id: @topic.id)
        expect(topic_user.posted?).to eq(true)
      end

    end
  end

  describe 'with category' do

    before do
      @category = Fabricate(:category)
    end

    it "should not increase the topic_count with no category" do
      expect { Fabricate(:topic, user: @category.user); @category.reload }.not_to change(@category, :topic_count)
    end

    it "should increase the category's topic_count" do
      expect { Fabricate(:topic, user: @category.user, category_id: @category.id); @category.reload }.to change(@category, :topic_count).by(1)
    end
  end

  describe 'meta data' do
    let(:topic) { Fabricate(:topic, meta_data: {'hello' => 'world'}) }

    it 'allows us to create a topic with meta data' do
      expect(topic.meta_data['hello']).to eq('world')
    end

    context 'updating' do

      context 'existing key' do
        before do
          topic.update_meta_data('hello' => 'bane')
        end

        it 'updates the key' do
          expect(topic.meta_data['hello']).to eq('bane')
        end
      end

      context 'new key' do
        before do
          topic.update_meta_data('city' => 'gotham')
        end

        it 'adds the new key' do
          expect(topic.meta_data['city']).to eq('gotham')
          expect(topic.meta_data['hello']).to eq('world')
        end

      end

      context 'new key' do
        before do
          topic.update_meta_data('other' => 'key')
          topic.save!
        end

        it "can be loaded" do
          expect(Topic.find(topic.id).meta_data["other"]).to eq("key")
        end

        it "is in sync with custom_fields" do
          expect(Topic.find(topic.id).custom_fields["other"]).to eq("key")
        end
      end


    end

  end

  describe 'after create' do

    let(:topic) { Fabricate(:topic) }

    it 'is a regular topic by default' do
      expect(topic.archetype).to eq(Archetype.default)
      expect(topic.has_summary).to eq(false)
      expect(topic.percent_rank).to eq(1.0)
      expect(topic).to be_visible
      expect(topic.pinned_at).to be_blank
      expect(topic).not_to be_closed
      expect(topic).not_to be_archived
      expect(topic.moderator_posts_count).to eq(0)
    end

    context 'post' do
      let(:post) { Fabricate(:post, topic: topic, user: topic.user) }

      it 'has the same archetype as the topic' do
        expect(post.archetype).to eq(topic.archetype)
      end
    end
  end

  describe 'change_category' do

    before do
      @topic = Fabricate(:topic)
      @category = Fabricate(:category, user: @topic.user)
      @user = @topic.user
    end

    describe 'without a previous category' do

      it 'should not change the topic_count when not changed' do
       expect { @topic.change_category_to_id(@topic.category.id); @category.reload }.not_to change(@category, :topic_count)
      end

      describe 'changed category' do
        before do
          @topic.change_category_to_id(@category.id)
          @category.reload
        end

        it 'changes the category' do
          expect(@topic.category).to eq(@category)
          expect(@category.topic_count).to eq(1)
        end

      end

      it "doesn't change the category when it can't be found" do
        @topic.change_category_to_id(12312312)
        expect(@topic.category_id).to eq(SiteSetting.uncategorized_category_id)
      end
    end

    describe 'with a previous category' do
      before do
        @topic.change_category_to_id(@category.id)
        @topic.reload
        @category.reload
      end

      it 'increases the topic_count' do
        expect(@category.topic_count).to eq(1)
      end

      it "doesn't change the topic_count when the value doesn't change" do
        expect { @topic.change_category_to_id(@category.id); @category.reload }.not_to change(@category, :topic_count)
      end

      it "doesn't reset the category when given a name that doesn't exist" do
        @topic.change_category_to_id(55556)
        expect(@topic.category_id).to be_present
      end

      describe 'to a different category' do
        before do
          @new_category = Fabricate(:category, user: @user, name: '2nd category')
          @topic.change_category_to_id(@new_category.id)
          @topic.reload
          @new_category.reload
          @category.reload
        end

        it "should increase the new category's topic count" do
          expect(@new_category.topic_count).to eq(1)
        end

        it "should lower the original category's topic count" do
          expect(@category.topic_count).to eq(0)
        end
      end

      context 'when allow_uncategorized_topics is false' do
        before do
          SiteSetting.stubs(:allow_uncategorized_topics).returns(false)
        end

        let!(:topic) { Fabricate(:topic, category: Fabricate(:category)) }

        it 'returns false' do
          expect(topic.change_category_to_id(nil)).to eq(false) # don't use "== false" here because it would also match nil
        end
      end

      describe 'when the category exists' do
        before do
          @topic.change_category_to_id(nil)
          @category.reload
        end

        it "resets the category" do
          expect(@topic.category_id).to eq(SiteSetting.uncategorized_category_id)
          expect(@category.topic_count).to eq(0)
        end
      end

    end

  end

  describe 'scopes' do
    describe '#by_most_recently_created' do
      it 'returns topics ordered by created_at desc, id desc' do
        now = Time.now
        a = Fabricate(:topic, created_at: now - 2.minutes)
        b = Fabricate(:topic, created_at: now)
        c = Fabricate(:topic, created_at: now)
        d = Fabricate(:topic, created_at: now - 2.minutes)
        expect(Topic.by_newest).to eq([c,b,d,a])
      end
    end

    describe '#created_since' do
      it 'returns topics created after some date' do
        now = Time.now
        a = Fabricate(:topic, created_at: now - 2.minutes)
        b = Fabricate(:topic, created_at: now - 1.minute)
        c = Fabricate(:topic, created_at: now)
        d = Fabricate(:topic, created_at: now + 1.minute)
        e = Fabricate(:topic, created_at: now + 2.minutes)
        expect(Topic.created_since(now)).not_to include a
        expect(Topic.created_since(now)).not_to include b
        expect(Topic.created_since(now)).not_to include c
        expect(Topic.created_since(now)).to include d
        expect(Topic.created_since(now)).to include e
      end
    end

    describe '#visible' do
      it 'returns topics set as visible' do
        a = Fabricate(:topic, visible: false)
        b = Fabricate(:topic, visible: true)
        c = Fabricate(:topic, visible: true)
        expect(Topic.visible).not_to include a
        expect(Topic.visible).to include b
        expect(Topic.visible).to include c
      end
    end
  end

  describe '#set_or_create_status_update' do
    let(:topic) { Fabricate.build(:topic) }

    let(:closing_topic) do
      Fabricate(:topic,
        topic_status_updates: [Fabricate(:topic_status_update, execute_at: 5.hours.from_now)]
      )
    end

    let(:admin) { Fabricate(:admin) }
    let(:trust_level_4) { Fabricate(:trust_level_4) }

    before { Discourse.stubs(:system_user).returns(admin) }

    it 'can take a number of hours as an integer' do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 72, by_user: admin)
        expect(topic.topic_status_updates.first.execute_at).to eq(3.days.from_now)
      end
    end

    it 'can take a number of hours as an integer, with timezone offset' do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 72, {by_user: admin, timezone_offset: 240})
        expect(topic.topic_status_updates.first.execute_at).to eq(3.days.from_now)
      end
    end

    it 'can take a number of hours as a string' do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '18', by_user: admin)
        expect(topic.topic_status_updates.first.execute_at).to eq(18.hours.from_now)
      end
    end

    it 'can take a number of hours as a string, with timezone offset' do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '18', {by_user: admin, timezone_offset: 240})
        expect(topic.topic_status_updates.first.execute_at).to eq(18.hours.from_now)
      end
    end

    it 'can take a number of hours as a string and can handle based on last post' do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '18', {by_user: admin, based_on_last_post: true})
        expect(topic.topic_status_updates.first.execute_at).to eq(18.hours.from_now)
      end
    end

    it "can take a time later in the day" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '13:00', {by_user: admin})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,20,13,0))
      end
    end

    it "can take a time later in the day, with timezone offset" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '13:00', {by_user: admin, timezone_offset: 240})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,20,17,0))
      end
    end

    it "can take a time for the next day" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '5:00', {by_user: admin})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,21,5,0))
      end
    end

    it "can take a time for the next day, with timezone offset" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '1:00', {by_user: admin, timezone_offset: 240})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,21,5,0))
      end
    end

    it "can take a timestamp for a future time" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '2013-11-22 5:00', {by_user: admin})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,22,5,0))
      end
    end

    it "can take a timestamp for a future time, with timezone offset" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '2013-11-22 5:00', {by_user: admin, timezone_offset: 240})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,22,9,0))
      end
    end

    it "sets a validation error when given a timestamp in the past" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '2013-11-19 5:00', {by_user: admin})

        expect(topic.topic_status_updates.first.execute_at).to eq(Time.zone.local(2013,11,19,5,0))
        expect(topic.topic_status_updates.first.errors[:execute_at]).to be_present
      end
    end

    it "can take a timestamp with timezone" do
      Timecop.freeze(now) do
        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], '2013-11-25T01:35:00-08:00', {by_user: admin})
        expect(topic.topic_status_updates.first.execute_at).to eq(Time.utc(2013,11,25,9,35))
      end
    end

    it 'sets topic status update user to given user if it is a staff or TL4 user' do
      topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 3, {by_user: admin})
      expect(topic.topic_status_updates.first.user).to eq(admin)
    end

    it 'sets topic status update user to given user if it is a TL4 user' do
      topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 3, {by_user: trust_level_4})
      expect(topic.topic_status_updates.first.user).to eq(trust_level_4)
    end

    it 'sets topic status update user to system user if given user is not staff or a TL4 user' do
      topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 3, {by_user: Fabricate.build(:user, id: 444)})
      expect(topic.topic_status_updates.first.user).to eq(admin)
    end

    it 'sets topic status update user to system user if user is not given and topic creator is not staff nor TL4 user' do
      topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 3)
      expect(topic.topic_status_updates.first.user).to eq(admin)
    end

    it 'sets topic status update user to topic creator if it is a staff user' do
      staff_topic = Fabricate.build(:topic, user: Fabricate.build(:admin, id: 999))
      staff_topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 3)
      expect(staff_topic.topic_status_updates.first.user_id).to eq(999)
    end

    it 'sets topic status update user to topic creator if it is a TL4 user' do
      tl4_topic = Fabricate.build(:topic, user: Fabricate.build(:trust_level_4, id: 998))
      tl4_topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 3)
      expect(tl4_topic.topic_status_updates.first.user_id).to eq(998)
    end

    it 'removes close topic status update if arg is nil' do
      closing_topic.set_or_create_status_update(TopicStatusUpdate.types[:close], nil)
      closing_topic.reload
      expect(closing_topic.topic_status_updates.first).to be_nil
    end

    it 'updates topic status update execute_at if it was already set to close' do
      Timecop.freeze(now) do
        closing_topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 48)
        expect(closing_topic.reload.topic_status_update.execute_at).to eq(2.days.from_now)
      end
    end

    it "does not update topic's topic status created_at it was already set to close" do
      expect{
        closing_topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 14)
      }.to_not change { closing_topic.topic_status_updates.first.created_at }
    end

    describe "when category's default auto close is set" do
      let(:category) { Fabricate(:category, auto_close_hours: 4) }
      let(:topic) { Fabricate(:topic, category: category) }

      it "should be able to override category's default auto close" do
        expect(topic.topic_status_updates.first.duration).to eq(4)

        topic.set_or_create_status_update(TopicStatusUpdate.types[:close], 2, by_user: admin)

        expect(topic.reload.closed).to eq(false)

        Timecop.travel(3.hours.from_now) do
          TopicStatusUpdate.ensure_consistency!
          expect(topic.reload.closed).to eq(true)
        end
      end
    end
  end

  describe 'for_digest' do
    let(:user) { Fabricate.build(:user) }

    it "returns none when there are no topics" do
      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to be_blank
    end

    it "doesn't return category topics" do
      Fabricate(:category)
      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to be_blank
    end

    it "returns regular topics" do
      topic = Fabricate(:topic)
      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to eq([topic])
    end

    it "doesn't return topics from muted categories" do
      user = Fabricate(:user)
      category = Fabricate(:category)
      Fabricate(:topic, category: category)

      CategoryUser.set_notification_level_for_category(user, CategoryUser.notification_levels[:muted], category.id)

      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to be_blank
    end

    it "doesn't return topics from suppressed categories" do
      user = Fabricate(:user)
      category = Fabricate(:category)
      Fabricate(:topic, category: category)

      SiteSetting.digest_suppress_categories = "#{category.id}"

      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to be_blank
    end

    it "doesn't return topics from TL0 users" do
      new_user = Fabricate(:user, trust_level: 0)
      Fabricate(:topic, user_id: new_user.id)

      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to be_blank
    end

    it "returns topics from TL0 users if given include_tl0" do
      new_user = Fabricate(:user, trust_level: 0)
      topic = Fabricate(:topic, user_id: new_user.id)

      expect(Topic.for_digest(user, 1.year.ago, top_order: true, include_tl0: true)).to eq([topic])
    end

    it "returns topics from TL0 users if enabled in preferences" do
      new_user = Fabricate(:user, trust_level: 0)
      topic = Fabricate(:topic, user_id: new_user.id)

      u = Fabricate(:user)
      u.user_option.include_tl0_in_digests = true

      expect(Topic.for_digest(u, 1.year.ago, top_order: true)).to eq([topic])
    end

    it "doesn't return topics with only muted tags" do
      user = Fabricate(:user)
      tag = Fabricate(:tag)
      TagUser.change(user.id, tag.id, TagUser.notification_levels[:muted])
      Fabricate(:topic, tags: [tag])

      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to be_blank
    end

    it "returns topics with both muted and not muted tags" do
      user = Fabricate(:user)
      muted_tag, other_tag = Fabricate(:tag), Fabricate(:tag)
      TagUser.change(user.id, muted_tag.id, TagUser.notification_levels[:muted])
      topic = Fabricate(:topic, tags: [muted_tag, other_tag])

      expect(Topic.for_digest(user, 1.year.ago, top_order: true)).to eq([topic])
    end

    it "sorts by category notification levels" do
      category1, category2 = Fabricate(:category), Fabricate(:category)
      2.times {|i| Fabricate(:topic, category: category1) }
      topic1 = Fabricate(:topic, category: category2)
      2.times {|i| Fabricate(:topic, category: category1) }
      CategoryUser.create(user: user, category: category2, notification_level: CategoryUser.notification_levels[:watching])
      for_digest = Topic.for_digest(user, 1.year.ago, top_order: true)
      expect(for_digest.first).to eq(topic1)
    end

    it "sorts by topic notification levels" do
      topics = []
      3.times {|i| topics << Fabricate(:topic) }
      user = Fabricate(:user)
      TopicUser.create(user_id: user.id, topic_id: topics[0].id, notification_level: TopicUser.notification_levels[:tracking])
      TopicUser.create(user_id: user.id, topic_id: topics[2].id, notification_level: TopicUser.notification_levels[:watching])
      for_digest = Topic.for_digest(user, 1.year.ago, top_order: true).pluck(:id)
      expect(for_digest).to eq([topics[2].id, topics[0].id, topics[1].id])
    end

  end

  describe 'secured' do
    it 'can remove secure groups' do
      category = Fabricate(:category, read_restricted: true)
      Fabricate(:topic, category: category)

      expect(Topic.secured(Guardian.new(nil)).count).to eq(0)
      expect(Topic.secured(Guardian.new(Fabricate(:admin))).count).to eq(2)

      # for_digest

      expect(Topic.for_digest(Fabricate(:user), 1.year.ago).count).to eq(0)
      expect(Topic.for_digest(Fabricate(:admin), 1.year.ago).count).to eq(1)
    end
  end

  describe 'all_allowed_users' do
    let(:group) { Fabricate(:group) }
    let(:topic) { Fabricate(:topic, allowed_groups: [group]) }
    let!(:allowed_user) { Fabricate(:user) }
    let!(:allowed_group_user) { Fabricate(:user) }
    let!(:moderator) { Fabricate(:user, moderator: true) }
    let!(:rando) { Fabricate(:user) }

    before do
      topic.allowed_users << allowed_user
      group.users << allowed_group_user
    end

    it 'includes allowed_users' do
      expect(topic.all_allowed_users).to include allowed_user
    end

    it 'includes allowed_group_users' do
      expect(topic.all_allowed_users).to include allowed_group_user
    end

    it 'includes moderators if flagged and a pm' do
      topic.stubs(:has_flags?).returns(true)
      topic.stubs(:private_message?).returns(true)
      expect(topic.all_allowed_users).to include moderator
    end

    it 'includes moderators if offical warning' do
      topic.stubs(:subtype).returns(TopicSubtype.moderator_warning)
      topic.stubs(:private_message?).returns(true)
      expect(topic.all_allowed_users).to include moderator
    end

    it 'does not include moderators if pm without flags' do
      topic.stubs(:private_message?).returns(true)
      expect(topic.all_allowed_users).not_to include moderator
    end

    it 'does not include moderators for regular topic' do
      expect(topic.all_allowed_users).not_to include moderator
    end

    it 'does not include randos' do
      expect(topic.all_allowed_users).not_to include rando
    end
  end

  describe '#listable_count_per_day' do
    before(:each) do
      Timecop.freeze
      Fabricate(:topic)
      Fabricate(:topic, created_at: 1.day.ago)
      Fabricate(:topic, created_at: 1.day.ago)
      Fabricate(:topic, created_at: 2.days.ago)
      Fabricate(:topic, created_at: 4.days.ago)
    end
    after(:each) do
      Timecop.return
    end
    let(:listable_topics_count_per_day) { {1.day.ago.to_date => 2, 2.days.ago.to_date => 1, Time.now.utc.to_date => 1 } }

    it 'collect closed interval listable topics count' do
      expect(Topic.listable_count_per_day(2.days.ago, Time.now)).to include(listable_topics_count_per_day)
      expect(Topic.listable_count_per_day(2.days.ago, Time.now)).not_to include({4.days.ago.to_date => 1})
    end
  end

  describe '#secure_category?' do
    let(:category){ Category.new }

    it "is true if the category is secure" do
      category.stubs(:read_restricted).returns(true)
      expect(Topic.new(:category => category)).to be_read_restricted_category
    end

    it "is false if the category is not secure" do
      category.stubs(:read_restricted).returns(false)
      expect(Topic.new(:category => category)).not_to be_read_restricted_category
    end

    it "is false if there is no category" do
      expect(Topic.new(:category => nil)).not_to be_read_restricted_category
    end
  end

  describe 'trash!' do
    context "its category's topic count" do
      let(:moderator) { Fabricate(:moderator) }
      let(:category) { Fabricate(:category) }

      it "subtracts 1 if topic is being deleted" do
        topic = Fabricate(:topic, category: category)
        expect { topic.trash!(moderator) }.to change { category.reload.topic_count }.by(-1)
      end

      it "doesn't subtract 1 if topic is already deleted" do
        topic = Fabricate(:topic, category: category, deleted_at: 1.day.ago)
        expect { topic.trash!(moderator) }.to_not change { category.reload.topic_count }
      end
    end
  end

  describe 'recover!' do
    context "its category's topic count" do
      let(:category) { Fabricate(:category) }

      it "adds 1 if topic is deleted" do
        topic = Fabricate(:topic, category: category, deleted_at: 1.day.ago)
        expect { topic.recover! }.to change { category.reload.topic_count }.by(1)
      end

      it "doesn't add 1 if topic is not deleted" do
        topic = Fabricate(:topic, category: category)
        expect { topic.recover! }.to_not change { category.reload.topic_count }
      end
    end
  end

  context "new user limits" do
    before do
      SiteSetting.max_topics_in_first_day = 1
      SiteSetting.max_replies_in_first_day = 1
      SiteSetting.stubs(:client_settings_json).returns(SiteSetting.client_settings_json_uncached)
      RateLimiter.stubs(:rate_limit_create_topic).returns(100)
      RateLimiter.stubs(:disabled?).returns(false)
      RateLimiter.clear_all!
    end

    it "limits new users to max_topics_in_first_day and max_posts_in_first_day" do
      start = Time.now.tomorrow.beginning_of_day

      freeze_time(start)

      user = Fabricate(:user)
      topic_id = create_post(user: user).topic_id

      freeze_time(start + 10.minutes)
      expect { create_post(user: user) }.to raise_error(RateLimiter::LimitExceeded)

      freeze_time(start + 20.minutes)
      create_post(user: user, topic_id: topic_id)

      freeze_time(start + 30.minutes)
      expect { create_post(user: user, topic_id: topic_id) }.to raise_error(RateLimiter::LimitExceeded)
    end

    it "starts counting when they make their first post/topic" do
      start = Time.now.tomorrow.beginning_of_day

      freeze_time(start)

      user = Fabricate(:user)

      freeze_time(start + 25.hours)
      topic_id = create_post(user: user).topic_id

      freeze_time(start + 26.hours)
      expect { create_post(user: user) }.to raise_error(RateLimiter::LimitExceeded)

      freeze_time(start + 27.hours)
      create_post(user: user, topic_id: topic_id)

      freeze_time(start + 28.hours)
      expect { create_post(user: user, topic_id: topic_id) }.to raise_error(RateLimiter::LimitExceeded)
    end
  end

  describe ".count_exceeds_minimun?" do
    before { SiteSetting.stubs(:minimum_topics_similar).returns(20) }

    context "when Topic count is geater than minimum_topics_similar" do
      it "should be true" do
        Topic.stubs(:count).returns(30)
        expect(Topic.count_exceeds_minimum?).to be_truthy
      end
    end

    context "when topic's count is less than minimum_topics_similar" do
      it "should be false" do
        Topic.stubs(:count).returns(10)
        expect(Topic.count_exceeds_minimum?).to_not be_truthy
      end
    end

  end

  describe "calculate_avg_time" do
    it "does not explode" do
      Topic.calculate_avg_time
      Topic.calculate_avg_time(1.day.ago)
    end
  end

  describe "expandable_first_post?" do

    let(:topic) { Fabricate.build(:topic) }

    it "is false if embeddable_host is blank" do
      expect(topic.expandable_first_post?).to eq(false)
    end

    describe 'with an emeddable host' do
      before do
        Fabricate(:embeddable_host)
        SiteSetting.embed_truncate = true
        topic.stubs(:has_topic_embed?).returns(true)
      end

      it "is true with the correct settings and topic_embed" do
        expect(topic.expandable_first_post?).to eq(true)
      end
      it "is false if embed_truncate? is false" do
        SiteSetting.embed_truncate = false
        expect(topic.expandable_first_post?).to eq(false)
      end

      it "is false if has_topic_embed? is false" do
        topic.stubs(:has_topic_embed?).returns(false)
        expect(topic.expandable_first_post?).to eq(false)
      end
    end

  end

  it "has custom fields" do
    topic = Fabricate(:topic)
    expect(topic.custom_fields["a"]).to eq(nil)

    topic.custom_fields["bob"] = "marley"
    topic.custom_fields["jack"] = "black"
    topic.save

    topic = Topic.find(topic.id)
    expect(topic.custom_fields).to eq({"bob" => "marley", "jack" => "black"})
  end

  it "doesn't validate the title again if it isn't changing" do
    SiteSetting.stubs(:min_topic_title_length).returns(5)
    topic = Fabricate(:topic, title: "Short")
    expect(topic).to be_valid

    SiteSetting.stubs(:min_topic_title_length).returns(15)
    topic.last_posted_at = 1.minute.ago
    expect(topic.save).to eq(true)
  end

  context 'invite by group manager' do
    let(:group_manager) { Fabricate(:user) }
    let(:group) { Fabricate(:group).tap { |g| g.add_owner(group_manager) } }
    let(:private_category)  { Fabricate(:private_category, group: group) }
    let(:group_private_topic) { Fabricate(:topic, category: private_category, user: group_manager) }

    context 'to an email' do
      let(:randolph) { 'randolph@duke.ooo' }

      it "should attach group to the invite" do
        invite = group_private_topic.invite(group_manager, randolph)
        expect(invite.groups).to eq([group])
      end
    end

    # should work for an existing user - give access, send notification
    context 'to an existing user' do
      let(:walter) { Fabricate(:walter_white) }

      it "should add user to the group" do
        expect(Guardian.new(walter).can_see?(group_private_topic)).to be_falsey
        expect { group_private_topic.invite(group_manager, walter.email) }.to raise_error(StandardError)
        expect(walter.groups).to include(group)
        expect(Guardian.new(walter).can_see?(group_private_topic)).to be_truthy
      end
    end
  end

  it "Correctly sets #message_archived?" do
    topic = Fabricate(:private_message_topic)
    user = topic.user

    expect(topic.message_archived?(user)).to eq(false)

    group = Fabricate(:group)
    group.add(user)

    TopicAllowedGroup.create!(topic_id: topic.id, group_id: group.id)
    GroupArchivedMessage.create!(topic_id: topic.id, group_id: group.id)

    expect(topic.message_archived?(user)).to eq(true)
  end

  it 'will trigger :topic_status_updated' do
    topic = Fabricate(:topic)
    user = topic.user
    user.admin = true
    @topic_status_event_triggered = false

    DiscourseEvent.on(:topic_status_updated) do
      @topic_status_event_triggered = true
    end

    topic.update_status('closed', true, user)
    topic.reload

    expect(@topic_status_event_triggered).to eq(true)
  end

  it 'allows users to normalize counts' do

    topic = Fabricate(:topic, last_posted_at: 1.year.ago)
    post1 = Fabricate(:post, topic: topic, post_number: 1)
    post2 = Fabricate(:post, topic: topic, post_type: Post.types[:whisper], post_number: 2)

    Topic.reset_all_highest!
    topic.reload

    expect(topic.posts_count).to eq(1)
    expect(topic.highest_post_number).to eq(post1.post_number)
    expect(topic.highest_staff_post_number).to eq(post2.post_number)
    expect(topic.last_posted_at).to be_within(1.second).of (post1.created_at)
  end

  context 'featured link' do
    before { SiteSetting.topic_featured_link_enabled = true }
    let(:topic) { Fabricate(:topic) }

    it 'can validate featured link' do
      topic.featured_link = ' invalid string'

      expect(topic).not_to be_valid
      expect(topic.errors[:featured_link]).to be_present
    end

    it 'can properly save the featured link' do
      topic.featured_link = '  https://github.com/discourse/discourse'

      expect(topic.save).to be_truthy
      expect(topic.featured_link).to eq('https://github.com/discourse/discourse')
    end

    context 'when category restricts present' do
      let!(:link_category) { Fabricate(:link_category) }
      let(:topic) { Fabricate(:topic) }
      let(:link_topic) { Fabricate(:topic, category: link_category) }

      it 'can save the featured link if it belongs to that category' do
        link_topic.featured_link = 'https://github.com/discourse/discourse'
        expect(link_topic.save).to be_truthy
        expect(link_topic.featured_link).to eq('https://github.com/discourse/discourse')
      end

      it 'can not save the featured link if category does not allow it' do
        topic.category = Fabricate(:category, topic_featured_link_allowed: false)
        topic.featured_link = 'https://github.com/discourse/discourse'
        expect(topic.save).to be_falsey
      end

      it 'if category changes to disallow it, topic remains valid' do
        t = Fabricate(:topic, category: link_category, featured_link: "https://github.com/discourse/discourse")

        link_category.topic_featured_link_allowed = false
        link_category.save!
        t.reload

        expect(t.valid?).to eq(true)
      end
    end
  end

  describe '#time_to_first_response' do
    it "should have no results if no topics in range" do
      expect(Topic.time_to_first_response_per_day(5.days.ago, Time.zone.now).count).to eq(0)
    end

    it "should have no results if there is only a topic with no replies" do
      topic = Fabricate(:topic, created_at: 1.hour.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1)
      expect(Topic.time_to_first_response_per_day(5.days.ago, Time.zone.now).count).to eq(0)
      expect(Topic.time_to_first_response_total).to eq(0)
    end

    it "should have no results if reply is from first poster" do
      topic = Fabricate(:topic, created_at: 1.hour.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 2)
      expect(Topic.time_to_first_response_per_day(5.days.ago, Time.zone.now).count).to eq(0)
      expect(Topic.time_to_first_response_total).to eq(0)
    end

    it "should have results if there's a topic with replies" do
      topic = Fabricate(:topic, created_at: 3.hours.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1, created_at: 3.hours.ago)
      Fabricate(:post, topic: topic, post_number: 2, created_at: 2.hours.ago)
      r = Topic.time_to_first_response_per_day(5.days.ago, Time.zone.now)
      expect(r.count).to eq(1)
      expect(r[0]["hours"].to_f.round).to eq(1)
      expect(Topic.time_to_first_response_total).to eq(1)
    end

    it "should only count regular posts as the first response" do
      topic = Fabricate(:topic, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, post_number: 2, created_at: 4.hours.ago, post_type: Post.types[:whisper])
      Fabricate(:post, topic: topic, post_number: 3, created_at: 3.hours.ago, post_type: Post.types[:moderator_action])
      Fabricate(:post, topic: topic, post_number: 4, created_at: 2.hours.ago, post_type: Post.types[:small_action])
      Fabricate(:post, topic: topic, post_number: 5, created_at: 1.hour.ago)
      r = Topic.time_to_first_response_per_day(5.days.ago, Time.zone.now)
      expect(r.count).to eq(1)
      expect(r[0]["hours"].to_f.round).to eq(4)
      expect(Topic.time_to_first_response_total).to eq(4)
    end
  end

  describe '#with_no_response' do
    it "returns nothing with no topics" do
      expect(Topic.with_no_response_per_day(5.days.ago, Time.zone.now).count).to eq(0)
    end

    it "returns 1 with one topic that has no replies" do
      topic = Fabricate(:topic, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1, created_at: 5.hours.ago)
      expect(Topic.with_no_response_per_day(5.days.ago, Time.zone.now).count).to eq(1)
      expect(Topic.with_no_response_total).to eq(1)
    end

    it "returns 1 with one topic that has no replies and author was changed on first post" do
      topic = Fabricate(:topic, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, user: Fabricate(:user), post_number: 1, created_at: 5.hours.ago)
      expect(Topic.with_no_response_per_day(5.days.ago, Time.zone.now).count).to eq(1)
      expect(Topic.with_no_response_total).to eq(1)
    end

    it "returns 1 with one topic that has a reply by the first poster" do
      topic = Fabricate(:topic, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 2, created_at: 2.hours.ago)
      expect(Topic.with_no_response_per_day(5.days.ago, Time.zone.now).count).to eq(1)
      expect(Topic.with_no_response_total).to eq(1)
    end

    it "returns 0 with a topic with 1 reply" do
      topic   = Fabricate(:topic, created_at: 5.hours.ago)
      post1   = Fabricate(:post, topic: topic, user: topic.user, post_number: 1, created_at: 5.hours.ago)
      post1   = Fabricate(:post, topic: topic, post_number: 2, created_at: 2.hours.ago)
      expect(Topic.with_no_response_per_day(5.days.ago, Time.zone.now).count).to eq(0)
      expect(Topic.with_no_response_total).to eq(0)
    end

    it "returns 1 with one topic that doesn't have regular replies" do
      topic = Fabricate(:topic, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, user: topic.user, post_number: 1, created_at: 5.hours.ago)
      Fabricate(:post, topic: topic, post_number: 2, created_at: 4.hours.ago, post_type: Post.types[:whisper])
      Fabricate(:post, topic: topic, post_number: 3, created_at: 3.hours.ago, post_type: Post.types[:moderator_action])
      Fabricate(:post, topic: topic, post_number: 4, created_at: 2.hours.ago, post_type: Post.types[:small_action])
      expect(Topic.with_no_response_per_day(5.days.ago, Time.zone.now).count).to eq(1)
      expect(Topic.with_no_response_total).to eq(1)
    end
  end
end
