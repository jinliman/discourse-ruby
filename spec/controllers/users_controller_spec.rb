require 'rails_helper'

describe UsersController do

  describe '.show' do

    context "anon" do

      let(:user) { Discourse.system_user }

      it "returns success" do
        xhr :get, :show, username: user.username, format: :json
        expect(response).to be_success
      end

      it "raises an error for anon when profiles are hidden" do
        SiteSetting.hide_user_profiles_from_public = true
        xhr :get, :show, username: user.username, format: :json
        expect(response).not_to be_success
      end

    end

    context "logged in" do

      let(:user) { log_in }

      it 'returns success' do
        xhr :get, :show, username: user.username, format: :json
        expect(response).to be_success
        json = JSON.parse(response.body)

        expect(json["user"]["has_title_badges"]).to eq(false)
      end

      it "returns not found when the username doesn't exist" do
        xhr :get, :show, username: 'madeuppity'
        expect(response).not_to be_success
      end

      it 'returns not found when the user is inactive' do
        inactive = Fabricate(:user, active: false)
        xhr :get, :show, username: inactive.username
        expect(response).not_to be_success
      end

      it "raises an error on invalid access" do
        Guardian.any_instance.expects(:can_see?).with(user).returns(false)
        xhr :get, :show, username: user.username
        expect(response).to be_forbidden
      end

      describe "user profile views" do
        let(:other_user) { Fabricate(:user) }

        it "should track a user profile view for a signed in user" do
          UserProfileView.expects(:add).with(other_user.user_profile.id, request.remote_ip, user.id)
          xhr :get, :show, username: other_user.username
        end

        it "should not track a user profile view for a user viewing his own profile" do
          UserProfileView.expects(:add).never
          xhr :get, :show, username: user.username
        end

        it "should track a user profile view for an anon user" do
          UserProfileView.expects(:add).with(other_user.user_profile.id, request.remote_ip, nil)
          xhr :get, :show, username: other_user.username
        end

        it "skips tracking" do
          UserProfileView.expects(:add).never
          xhr :get, :show, { username: user.username, skip_track_visit: true }
        end
      end

      context "fetching a user by external_id" do
        before { user.create_single_sign_on_record(external_id: '997', last_payload: '') }

        it "returns fetch for a matching external_id" do
          xhr :get, :show, external_id: '997'
          expect(response).to be_success
        end

        it "returns not found when external_id doesn't match" do
          xhr :get, :show, external_id: '99'
          expect(response).not_to be_success
        end
      end

    end

  end

  describe '.user_preferences_redirect' do
    it 'requires the user to be logged in' do
      expect { get :user_preferences_redirect }.to raise_error(Discourse::NotLoggedIn)
    end

    it "redirects to their profile when logged in" do
      user = log_in
      get :user_preferences_redirect
      expect(response).to redirect_to("/u/#{user.username_lower}/preferences")
    end
  end

  describe '.activate_account' do
    before do
      UsersController.any_instance.stubs(:honeypot_or_challenge_fails?).returns(false)
    end

    context 'invalid token' do

      it 'return success' do
        EmailToken.expects(:confirm).with('asdfasdf').returns(nil)
        put :perform_account_activation, token: 'asdfasdf'
        expect(response).to be_success
        expect(flash[:error]).to be_present
      end
    end

    context 'valid token' do
      let(:user) { Fabricate(:user) }

      context 'welcome message' do
        before do
          EmailToken.expects(:confirm).with('asdfasdf').returns(user)
        end

        it 'enqueues a welcome message if the user object indicates so' do
          user.send_welcome_message = true
          user.expects(:enqueue_welcome_message).with('welcome_user')
          put :perform_account_activation, token: 'asdfasdf'
        end

        it "doesn't enqueue the welcome message if the object returns false" do
          user.send_welcome_message = false
          user.expects(:enqueue_welcome_message).with('welcome_user').never
          put :perform_account_activation, token: 'asdfasdf'
        end
      end

      context "honeypot" do
        it "raises an error if the honeypot is invalid" do
          UsersController.any_instance.stubs(:honeypot_or_challenge_fails?).returns(true)
          put :perform_account_activation, token: 'asdfasdf'
          expect(response).not_to be_success
        end
      end

      context 'response' do
        before do
          Guardian.any_instance.expects(:can_access_forum?).returns(true)
          EmailToken.expects(:confirm).with('asdfasdf').returns(user)
          put :perform_account_activation, token: 'asdfasdf'
        end

        it 'correctly logs on user' do
          expect(response).to be_success
          expect(flash[:error]).to be_blank
          expect(session[:current_user_id]).to be_present
          expect(assigns[:needs_approval]).to be_blank
        end

      end

      context 'user is not approved' do
        before do
          Guardian.any_instance.expects(:can_access_forum?).returns(false)
          EmailToken.expects(:confirm).with('asdfasdf').returns(user)
          put :perform_account_activation, token: 'asdfasdf'
        end

        it 'returns success' do
          expect(response).to be_success
        end

        it 'sets @needs_approval' do
          expect(assigns[:needs_approval]).to be_present
        end

        it "doesn't set an error" do
          expect(flash[:error]).to be_blank
        end

        it "doesn't log the user in" do
          expect(session[:current_user_id]).to be_blank
        end
      end

    end
  end

  describe '#perform_account_activation' do
    describe 'when cookies contains a destination URL' do
      let(:token) { 'asdadwewq' }
      let(:user) { Fabricate(:user) }

      before do
        UsersController.any_instance.stubs(:honeypot_or_challenge_fails?).returns(false)
        EmailToken.expects(:confirm).with(token).returns(user)
      end

      it 'should redirect to the URL' do
        destination_url = 'http://thisisasite.com/somepath'
        request.cookies[:destination_url] = destination_url

        put :perform_account_activation, token: token

        expect(response).to redirect_to(destination_url)
      end
    end
  end

  describe '.password_reset' do
    let(:user) { Fabricate(:user) }

    context "you can view it even if login is required" do
      it "returns success" do
        SiteSetting.login_required = true
        get :password_reset, token: 'asdfasdf'
        expect(response).to be_success
      end
    end

    context 'missing token' do
      before do
        get :password_reset, token: SecureRandom.hex
      end

      it 'disallows login' do
        expect(assigns[:error]).to be_present
        expect(session[:current_user_id]).to be_blank
        expect(response).to be_success
        expect(response).to render_template(layout: 'no_ember')
      end
    end

    context 'invalid token' do
      before do
        get :password_reset, token: "evil_trout!"
      end

      it 'disallows login' do
        expect(assigns[:error]).to be_present
        expect(session[:current_user_id]).to be_blank
        expect(response).to be_success
        expect(response).to render_template(layout: 'no_ember')
      end
    end

    context 'valid token' do
      context 'when rendered' do
        render_views

        it 'renders referrer never on get requests' do
          user = Fabricate(:user)
          token = user.email_tokens.create(email: user.email).token
          get :password_reset, token: token

          expect(response.body).to include('<meta name="referrer" content="never">')
        end
      end

      it 'returns success' do
        user = Fabricate(:user)
        user_auth_token = UserAuthToken.generate!(user_id: user.id)
        token = user.email_tokens.create(email: user.email).token

        get :password_reset, token: token
        put :password_reset, token: token, password: 'hg9ow8yhg98o'

        expect(response).to be_success
        expect(assigns[:error]).to be_blank

        user.reload

        expect(session["password-#{token}"]).to be_blank
        expect(UserAuthToken.where(id: user_auth_token.id).count).to eq(0)
      end

      it 'disallows double password reset' do
        user = Fabricate(:user)
        token = user.email_tokens.create(email: user.email).token

        get :password_reset, token: token
        put :password_reset, token: token, password: 'hg9ow8yHG32O'
        put :password_reset, token: token, password: 'test123987AsdfXYZ'

        user.reload
        expect(user.confirm_password?('hg9ow8yHG32O')).to eq(true)

        # logged in now
        expect(user.user_auth_tokens.count).to eq(1)
      end

      it "redirects to the wizard if you're the first admin" do
        user = Fabricate(:admin)
        token = user.email_tokens.create(email: user.email).token
        get :password_reset, token: token
        put :password_reset, token: token, password: 'hg9ow8yhg98oadminlonger'
        expect(response).to be_redirect
      end

      it "doesn't invalidate the token when loading the page" do
        user = Fabricate(:user)
        user_token = UserAuthToken.generate!(user_id: user.id)

        email_token = user.email_tokens.create(email: user.email)

        get :password_reset, token: email_token.token

        email_token.reload

        expect(email_token.confirmed).to eq(false)
        expect(UserAuthToken.where(id: user_token.id).count).to eq(1)
      end
    end

    context 'submit change' do
      let(:token) { EmailToken.generate_token }
      before do
        EmailToken.expects(:confirm).with(token).returns(user)
      end

      it "fails when the password is blank" do
        put :password_reset, token: token, password: ''
        expect(assigns(:user).errors).to be_present
        expect(session[:current_user_id]).to be_blank
      end

      it "fails when the password is too long" do
        put :password_reset, token: token, password: ('x' * (User.max_password_length + 1))
        expect(assigns(:user).errors).to be_present
        expect(session[:current_user_id]).to be_blank
      end

      it "logs in the user" do
        put :password_reset, token: token, password: 'ksjafh928r'
        expect(assigns(:user).errors).to be_blank
        expect(session[:current_user_id]).to be_present
      end

      it "doesn't log in the user when not approved" do
        SiteSetting.must_approve_users = true
        put :password_reset, token: token, password: 'ksjafh928r'
        expect(assigns(:user).errors).to be_blank
        expect(session[:current_user_id]).to be_blank
      end
    end
  end

  describe '.confirm_email_token' do
    let(:user) { Fabricate(:user) }

    it "token doesn't match any records" do
      email_token = user.email_tokens.create(email: user.email)
      get :confirm_email_token, token: SecureRandom.hex, format: :json
      expect(response).to be_success
      expect(email_token.reload.confirmed).to eq(false)
    end

    it "token matches" do
      email_token = user.email_tokens.create(email: user.email)
      get :confirm_email_token, token: email_token.token, format: :json
      expect(response).to be_success
      expect(email_token.reload.confirmed).to eq(true)
    end
  end

  describe '.admin_login' do
    let(:admin) { Fabricate(:admin) }
    let(:user) { Fabricate(:user) }

    context 'enqueues mail' do
      it 'enqueues mail with admin email and sso enabled' do
        Jobs.expects(:enqueue).with(:critical_user_email, has_entries(type: :admin_login, user_id: admin.id))
        put :admin_login, email: admin.email
      end
    end

    context 'logs in admin' do
      it 'does not log in admin with invalid token' do
        SiteSetting.enable_sso = true
        get :admin_login, token: "invalid"
        expect(session[:current_user_id]).to be_blank
      end

      it 'does log in admin with valid token and SSO disabled' do
        SiteSetting.enable_sso = false
        token = admin.email_tokens.create(email: admin.email).token

        get :admin_login, token: token
        expect(response).to redirect_to('/')
        expect(session[:current_user_id]).to eq(admin.id)
      end

      it 'logs in admin with valid token and SSO enabled' do
        SiteSetting.enable_sso = true
        token = admin.email_tokens.create(email: admin.email).token

        get :admin_login, token: token
        expect(response).to redirect_to('/')
        expect(session[:current_user_id]).to eq(admin.id)
      end
    end
  end

  describe '#toggle_anon' do
    it 'allows you to toggle anon if enabled' do
      SiteSetting.allow_anonymous_posting = true

      user = log_in
      user.trust_level = 1
      user.save

      post :toggle_anon
      expect(response).to be_success
      expect(session[:current_user_id]).to eq(AnonymousShadowCreator.get(user).id)

      post :toggle_anon
      expect(response).to be_success
      expect(session[:current_user_id]).to eq(user.id)

    end
  end

  describe '#create' do

    before do
      UsersController.any_instance.stubs(:honeypot_value).returns(nil)
      UsersController.any_instance.stubs(:challenge_value).returns(nil)
      SiteSetting.allow_new_registrations = true
      @user = Fabricate.build(:user)
      @user.password = "strongpassword"
    end

    let(:post_user_params) do
      { name: @user.name,
        username: @user.username,
        password: "strongpassword",
        email: @user.email }
    end

    def post_user
      xhr :post, :create, post_user_params
    end

    context 'when creating a user' do
      it 'sets the user locale to I18n.locale' do
        SiteSetting.default_locale = 'en'
        I18n.stubs(:locale).returns(:fr)
        post_user
        expect(User.find_by(username: @user.username).locale).to eq('fr')
      end
    end

    context 'when creating a non active user (unconfirmed email)' do

      it 'returns a 500 when local logins are disabled' do
        SiteSetting.enable_local_logins = false
        post_user

        expect(response.status).to eq(500)
      end

      it 'returns an error when new registrations are disabled' do
        SiteSetting.allow_new_registrations = false
        post_user
        json = JSON.parse(response.body)
        expect(json['success']).to eq(false)
        expect(json['message']).to be_present
      end

      it 'creates a user correctly' do
        Jobs.expects(:enqueue).with(:critical_user_email, has_entries(type: :signup))
        User.any_instance.expects(:enqueue_welcome_message).with('welcome_user').never

        post_user

        expect(JSON.parse(response.body)['active']).to be_falsey

        # should save user_created_message in session
        expect(session["user_created_message"]).to be_present
      end

      context "and 'must approve users' site setting is enabled" do
        before { SiteSetting.must_approve_users = true }

        it 'does not enqueue an email' do
          Jobs.expects(:enqueue).never
          post_user
        end

        it 'does not login the user' do
          post_user
          expect(session[:current_user_id]).to be_blank
        end

        it 'indicates the user is not active in the response' do
          post_user
          expect(JSON.parse(response.body)['active']).to be_falsey
        end

        it "shows the 'waiting approval' message" do
          post_user
          expect(JSON.parse(response.body)['message']).to eq(I18n.t 'login.wait_approval')
        end
      end
    end

    context "creating as active" do
      it "won't create the user as active" do
        xhr :post, :create, post_user_params.merge(active: true)
        expect(JSON.parse(response.body)['active']).to be_falsey
      end

      context "with a regular api key" do
        let(:user) { Fabricate(:user) }
        let(:api_key) { Fabricate(:api_key, user: user) }

        it "won't create the user as active with a regular key" do
          xhr :post, :create, post_user_params.merge(active: true, api_key: api_key.key)
          expect(JSON.parse(response.body)['active']).to be_falsey
        end
      end

      context "with an admin api key" do
        let(:user) { Fabricate(:admin) }
        let(:api_key) { Fabricate(:api_key, user: user) }

        it "creates the user as active with a regular key" do
          xhr :post, :create, post_user_params.merge(active: true, api_key: api_key.key)
          expect(JSON.parse(response.body)['active']).to be_truthy
        end

        it "won't create the developer as active" do
          UsernameCheckerService.expects(:is_developer?).returns(true)

          xhr :post, :create, post_user_params.merge(active: true, api_key: api_key.key)
          expect(JSON.parse(response.body)['active']).to be_falsy
        end
      end
    end

    context "creating as staged" do
      it "won't create the user as staged" do
        xhr :post, :create, post_user_params.merge(staged: true)
        new_user = User.where(username: post_user_params[:username]).first
        expect(new_user.staged?).to eq(false)
      end

      context "with a regular api key" do
        let(:user) { Fabricate(:user) }
        let(:api_key) { Fabricate(:api_key, user: user) }

        it "won't create the user as staged with a regular key" do
          xhr :post, :create, post_user_params.merge(staged: true, api_key: api_key.key)
          new_user = User.where(username: post_user_params[:username]).first
          expect(new_user.staged?).to eq(false)
        end
      end

      context "with an admin api key" do
        let(:user) { Fabricate(:admin) }
        let(:api_key) { Fabricate(:api_key, user: user) }

        it "creates the user as staged with a regular key" do
          xhr :post, :create, post_user_params.merge(staged: true, api_key: api_key.key)

          new_user = User.where(username: post_user_params[:username]).first
          expect(new_user.staged?).to eq(true)
        end

        it "won't create the developer as staged" do
          UsernameCheckerService.expects(:is_developer?).returns(true)
          xhr :post, :create, post_user_params.merge(staged: true, api_key: api_key.key)

          new_user = User.where(username: post_user_params[:username]).first
          expect(new_user.staged?).to eq(false)
        end
      end
    end

    context 'when creating an active user (confirmed email)' do
      before { User.any_instance.stubs(:active?).returns(true) }

      it 'enqueues a welcome email' do
        User.any_instance.expects(:enqueue_welcome_message).with('welcome_user')
        post_user

        # should save user_created_message in session
        expect(session["user_created_message"]).to be_present
      end

      it "shows the 'active' message" do
        User.any_instance.expects(:enqueue_welcome_message)
        post_user
        expect(JSON.parse(response.body)['message']).to eq(
          I18n.t 'login.active'
        )
      end

      it "should be logged in" do
        User.any_instance.expects(:enqueue_welcome_message)
        post_user
        expect(session[:current_user_id]).to be_present
      end

      it 'indicates the user is active in the response' do
        User.any_instance.expects(:enqueue_welcome_message)
        post_user
        expect(JSON.parse(response.body)['active']).to be_truthy
      end

      it 'returns 500 status when new registrations are disabled' do
        SiteSetting.allow_new_registrations = false

        post_user

        json = JSON.parse(response.body)
        expect(json['success']).to eq(false)
        expect(json['message']).to be_present
      end

      context 'authentication records for' do

        it 'should create twitter user info if required' do
          SiteSetting.must_approve_users = true
          SiteSetting.enable_twitter_logins = true
          twitter_auth = { twitter_user_id: 42, twitter_screen_name: "bruce" }
          auth = session[:authentication] = {}
          auth[:authenticator_name] = 'twitter'
          auth[:extra_data] = twitter_auth

          post_user

          expect(TwitterUserInfo.count).to eq(1)
        end
      end
    end

    context 'after success' do
      before { post_user }

      it 'should succeed' do
        is_expected.to respond_with(:success)
      end

      it 'has the proper JSON' do
        json = JSON::parse(response.body)
        expect(json["success"]).to eq(true)
      end

      it 'should not result in an active account' do
        expect(User.find_by(username: @user.username).active).to eq(false)
      end
    end

    shared_examples 'honeypot fails' do
      it 'should not create a new user' do
        expect {
          xhr :post, :create, create_params
        }.to_not change { User.count }
      end

      it 'should not send an email' do
        User.any_instance.expects(:enqueue_welcome_message).never
        xhr :post, :create, create_params
      end

      it 'should say it was successful' do
        xhr :post, :create, create_params
        json = JSON::parse(response.body)
        expect(json["success"]).to eq(true)

        # should not change the session
        expect(session["user_created_message"]).to be_blank
      end
    end

    context 'when honeypot value is wrong' do
      before do
        UsersController.any_instance.stubs(:honeypot_value).returns('abc')
      end
      let(:create_params) { {name: @user.name, username: @user.username, password: "strongpassword", email: @user.email, password_confirmation: 'wrong'} }
      include_examples 'honeypot fails'
    end

    context 'when challenge answer is wrong' do
      before do
        UsersController.any_instance.stubs(:challenge_value).returns('abc')
      end
      let(:create_params) { {name: @user.name, username: @user.username, password: "strongpassword", email: @user.email, challenge: 'abc'} }
      include_examples 'honeypot fails'
    end

    context "when 'invite only' setting is enabled" do
      before { SiteSetting.invite_only = true }

      let(:create_params) {{
        name: @user.name,
        username: @user.username,
        password: 'strongpassword',
        email: @user.email
      }}

      include_examples 'honeypot fails'
    end

    shared_examples 'failed signup' do
      it 'should not create a new User' do
        expect { xhr :post, :create, create_params }.to_not change { User.count }
      end

      it 'should report failed' do
        xhr :post, :create, create_params
        json = JSON::parse(response.body)
        expect(json["success"]).not_to eq(true)

        # should not change the session
        expect(session["user_created_message"]).to be_blank
      end
    end

    context 'when password is blank' do
      let(:create_params) { {name: @user.name, username: @user.username, password: "", email: @user.email} }
      include_examples 'failed signup'
    end

    context 'when password is too long' do
      let(:create_params) { {name: @user.name, username: @user.username, password: "x" * (User.max_password_length + 1), email: @user.email} }
      include_examples 'failed signup'
    end

    context 'when password param is missing' do
      let(:create_params) { {name: @user.name, username: @user.username, email: @user.email} }
      include_examples 'failed signup'
    end

    context 'with a reserved username' do
      let(:create_params) { {name: @user.name, username: 'Reserved', email: @user.email, password: "x" * 20} }
      before { SiteSetting.reserved_usernames = 'a|reserved|b' }
      after { SiteSetting.reserved_usernames = nil }
      include_examples 'failed signup'
    end

    context 'when an Exception is raised' do
      [ ActiveRecord::StatementInvalid,
        RestClient::Forbidden ].each do |exception|
        before { User.any_instance.stubs(:save).raises(exception) }

        let(:create_params) {
          { name: @user.name, username: @user.username,
            password: "strongpassword", email: @user.email}
        }

        include_examples 'failed signup'
      end
    end

    context "with custom fields" do
      let!(:user_field) { Fabricate(:user_field) }
      let!(:another_field) { Fabricate(:user_field) }
      let!(:optional_field) { Fabricate(:user_field, required: false) }

      context "without a value for the fields" do
        let(:create_params) { {name: @user.name, password: 'watwatwat', username: @user.username, email: @user.email} }
        include_examples 'failed signup'
      end

      context "with values for the fields" do
        let(:create_params) { {
          name: @user.name,
          password: 'suChS3cuRi7y',
          username: @user.username,
          email: @user.email,
          user_fields: {
            user_field.id.to_s => 'value1',
            another_field.id.to_s => 'value2',
          }
        } }

        it "should succeed without the optional field" do
          xhr :post, :create, create_params
          expect(response).to be_success
          inserted = User.where(email: @user.email).first
          expect(inserted).to be_present
          expect(inserted.custom_fields).to be_present
          expect(inserted.custom_fields["user_field_#{user_field.id}"]).to eq('value1')
          expect(inserted.custom_fields["user_field_#{another_field.id}"]).to eq('value2')
          expect(inserted.custom_fields["user_field_#{optional_field.id}"]).to be_blank
        end

        it "should succeed with the optional field" do
          create_params[:user_fields][optional_field.id.to_s] = 'value3'
          xhr :post, :create, create_params.merge(create_params)
          expect(response).to be_success
          inserted = User.where(email: @user.email).first
          expect(inserted).to be_present
          expect(inserted.custom_fields).to be_present
          expect(inserted.custom_fields["user_field_#{user_field.id}"]).to eq('value1')
          expect(inserted.custom_fields["user_field_#{another_field.id}"]).to eq('value2')
          expect(inserted.custom_fields["user_field_#{optional_field.id}"]).to eq('value3')
        end

        it "trims excessively long fields" do
          create_params[:user_fields][optional_field.id.to_s] = ('x' * 3000)
          xhr :post, :create, create_params.merge(create_params)
          expect(response).to be_success
          inserted = User.where(email: @user.email).first

          val = inserted.custom_fields["user_field_#{optional_field.id}"]
          expect(val.length).to eq(UserField.max_length)
        end
      end
    end

    context "with only optional custom fields" do
      let!(:user_field) { Fabricate(:user_field, required: false) }

      context "without values for the fields" do
        let(:create_params) { {
          name: @user.name,
          password: 'suChS3cuRi7y',
          username: @user.username,
          email: @user.email,
        } }

        it "should succeed" do
          xhr :post, :create, create_params
          expect(response).to be_success
          inserted = User.where(email: @user.email).first
          expect(inserted).to be_present
          expect(inserted.custom_fields).not_to be_present
          expect(inserted.custom_fields["user_field_#{user_field.id}"]).to be_blank
        end
      end
    end

    context "when taking over a staged account" do
      let!(:staged) { Fabricate(:staged, email: "staged@account.com") }

      it "succeeds" do
        xhr :post, :create, email: staged.email, username: "zogstrip", password: "P4ssw0rd$$"
        result = ::JSON.parse(response.body)
        expect(result["success"]).to eq(true)
        expect(User.find_by(email: staged.email).staged).to eq(false)
      end
    end

  end

  context '.username' do
    it 'raises an error when not logged in' do
      expect { xhr :put, :username, username: 'somename' }.to raise_error(Discourse::NotLoggedIn)
    end

    context 'while logged in' do
      let(:old_username) { "OrigUsrname" }
      let(:new_username) { "#{old_username}1234" }
      let(:user) { Fabricate(:user, username: old_username) }

      before do
        user.username = old_username
        log_in_user(user)
      end

      it 'raises an error without a new_username param' do
        expect { xhr :put, :username, username: user.username }.to raise_error(ActionController::ParameterMissing)
        expect(user.reload.username).to eq(old_username)
      end

      it 'raises an error when you don\'t have permission to change the username' do
        Guardian.any_instance.expects(:can_edit_username?).with(user).returns(false)
        xhr :put, :username, username: user.username, new_username: new_username
        expect(response).to be_forbidden
        expect(user.reload.username).to eq(old_username)
      end

      # Bad behavior, this should give a real JSON error, not an InvalidParameters
      it 'raises an error when change_username fails' do
        User.any_instance.expects(:save).returns(false)
        expect { xhr :put, :username, username: user.username, new_username: new_username }.to raise_error(Discourse::InvalidParameters)
        expect(user.reload.username).to eq(old_username)
      end

      it 'should succeed in normal circumstances' do
        xhr :put, :username, username: user.username, new_username: new_username
        expect(response).to be_success
        expect(user.reload.username).to eq(new_username)
      end

      skip 'should fail if the user is old', 'ensure_can_edit_username! is not throwing' do
        # Older than the change period and >1 post
        user.created_at = Time.now - (SiteSetting.username_change_period + 1).days
        user.stubs(:post_count).returns(200)
        expect(Guardian.new(user).can_edit_username?(user)).to eq(false)

        xhr :put, :username, username: user.username, new_username: new_username

        expect(response).to be_forbidden
        expect(user.reload.username).to eq(old_username)
      end

      it 'should create a staff action log when a staff member changes the username' do
        acting_user = Fabricate(:admin)
        log_in_user(acting_user)
        xhr :put, :username, username: user.username, new_username: new_username
        expect(response).to be_success
        expect(UserHistory.where(action: UserHistory.actions[:change_username], target_user_id: user.id, acting_user_id: acting_user.id)).to be_present
        expect(user.reload.username).to eq(new_username)
      end

      it 'should return a JSON response with the updated username' do
        xhr :put, :username, username: user.username, new_username: new_username
        expect(::JSON.parse(response.body)['username']).to eq(new_username)
      end

    end
  end

  context '.check_username' do
    it 'raises an error without any parameters' do
      expect { xhr :get, :check_username }.to raise_error(ActionController::ParameterMissing)
    end

    shared_examples 'when username is unavailable' do
      it 'should return success' do
        expect(response).to be_success
      end

      it 'should return available as false in the JSON' do
        expect(::JSON.parse(response.body)['available']).to eq(false)
      end

      it 'should return a suggested username' do
        expect(::JSON.parse(response.body)['suggestion']).to be_present
      end
    end

    shared_examples 'when username is available' do
      it 'should return success' do
        expect(response).to be_success
      end

      it 'should return available in the JSON' do
        expect(::JSON.parse(response.body)['available']).to eq(true)
      end
    end

    it 'returns nothing when given an email param but no username' do
      xhr :get, :check_username, email: 'dood@example.com'
      expect(response).to be_success
    end

    context 'username is available' do
      before do
        xhr :get, :check_username, username: 'BruceWayne'
      end
      include_examples 'when username is available'
    end

    context 'username is unavailable' do
      let!(:user) { Fabricate(:user) }
      before do
        xhr :get, :check_username, username: user.username
      end
      include_examples 'when username is unavailable'
    end

    shared_examples 'checking an invalid username' do
      it 'should return success' do
        expect(response).to be_success
      end

      it 'should not return an available key' do
        expect(::JSON.parse(response.body)['available']).to eq(nil)
      end

      it 'should return an error message' do
        expect(::JSON.parse(response.body)['errors']).not_to be_empty
      end
    end

    context 'has invalid characters' do
      before do
        xhr :get, :check_username, username: 'bad username'
      end
      include_examples 'checking an invalid username'

      it 'should return the invalid characters message' do
        expect(::JSON.parse(response.body)['errors']).to include(I18n.t(:'user.username.characters'))
      end
    end

    context 'is too long' do
      before do
        xhr :get, :check_username, username: generate_username(User.username_length.last + 1)
      end
      include_examples 'checking an invalid username'

      it 'should return the "too long" message' do
        expect(::JSON.parse(response.body)['errors']).to include(I18n.t(:'user.username.long', max: User.username_length.end))
      end
    end

    describe 'different case of existing username' do
      context "it's my username" do
        let!(:user) { Fabricate(:user, username: 'hansolo') }
        before do
          log_in_user(user)
          xhr :get, :check_username, username: 'HanSolo'
        end
        include_examples 'when username is available'
      end

      context "it's someone else's username" do
        let!(:user) { Fabricate(:user, username: 'hansolo') }
        before do
          log_in
          xhr :get, :check_username, username: 'HanSolo'
        end
        include_examples 'when username is unavailable'
      end

      context "an admin changing it for someone else" do
        let!(:user) { Fabricate(:user, username: 'hansolo') }
        before do
          log_in_user(Fabricate(:admin))
          xhr :get, :check_username, username: 'HanSolo', for_user_id: user.id
        end
        include_examples 'when username is available'
      end
    end
  end

  describe '#invited' do
    it 'returns success' do
      user = Fabricate(:user)

      xhr :get, :invited, username: user.username

      expect(response).to be_success
    end

    it 'filters by email' do
      inviter = Fabricate(:user)
      invitee = Fabricate(:user)
      _invite = Fabricate(
        :invite,
        email: 'billybob@example.com',
        invited_by: inviter,
        user: invitee
      )
      Fabricate(
        :invite,
        email: 'jimtom@example.com',
        invited_by: inviter,
        user: invitee
      )

      xhr :get, :invited, username: inviter.username, search: 'billybob'

      invites = JSON.parse(response.body)['invites']
      expect(invites.size).to eq(1)
      expect(invites.first).to include('email' => 'billybob@example.com')
    end

    it 'filters by username' do
      inviter = Fabricate(:user)
      invitee = Fabricate(:user, username: 'billybob')
      _invite = Fabricate(
        :invite,
        invited_by: inviter,
        email: 'billybob@example.com',
        user: invitee
      )
      Fabricate(
        :invite,
        invited_by: inviter,
        user: Fabricate(:user, username: 'jimtom')
      )

      xhr :get, :invited, username: inviter.username, search: 'billybob'

      invites = JSON.parse(response.body)['invites']
      expect(invites.size).to eq(1)
      expect(invites.first).to include('email' => 'billybob@example.com')
    end

    context 'with guest' do
      context 'with pending invites' do
        it 'does not return invites' do
          inviter = Fabricate(:user)
          Fabricate(:invite, invited_by: inviter)

          xhr :get, :invited, username: inviter.username, filter: 'pending'

          invites = JSON.parse(response.body)['invites']
          expect(invites).to be_empty
        end
      end

      context 'with redeemed invites' do
        it 'returns invites' do
          inviter = Fabricate(:user)
          invitee = Fabricate(:user)
          invite = Fabricate(:invite, invited_by: inviter, user: invitee)

          xhr :get, :invited, username: inviter.username

          invites = JSON.parse(response.body)['invites']
          expect(invites.size).to eq(1)
          expect(invites.first).to include('email' => invite.email)
        end
      end
    end

    context 'with authenticated user' do
      context 'with pending invites' do
        context 'with permission to see pending invites' do
          it 'returns invites' do
            user = log_in
            inviter = Fabricate(:user)
            invite = Fabricate(:invite, invited_by: inviter)
            stub_guardian(user) do |guardian|
              guardian.stubs(:can_see_invite_details?).
                with(inviter).returns(true)
            end

            xhr :get, :invited, username: inviter.username, filter: 'pending'

            invites = JSON.parse(response.body)['invites']
            expect(invites.size).to eq(1)
            expect(invites.first).to include("email" => invite.email)
          end
        end

        context 'without permission to see pending invites' do
          it 'does not return invites' do
            user = log_in
            inviter = Fabricate(:user)
            _invitee = Fabricate(:user)
            Fabricate(:invite, invited_by: inviter)
            stub_guardian(user) do |guardian|
              guardian.stubs(:can_see_invite_details?).
                with(inviter).returns(false)
            end

            xhr :get, :invited, username: inviter.username, filter: 'pending'

            json = JSON.parse(response.body)['invites']
            expect(json).to be_empty
          end
        end
      end

      context 'with redeemed invites' do
        it 'returns invites' do
          _user = log_in
          inviter = Fabricate(:user)
          invitee = Fabricate(:user)
          invite = Fabricate(:invite, invited_by: inviter, user: invitee)

          xhr :get, :invited, username: inviter.username

          invites = JSON.parse(response.body)['invites']
          expect(invites.size).to eq(1)
          expect(invites.first).to include('email' => invite.email)
        end
      end
    end
  end

  describe '#update' do
    context 'with guest' do
      it 'raises an error' do
        expect do
          xhr :put, :update, username: 'guest'
        end.to raise_error(Discourse::NotLoggedIn)
      end
    end

    context "as a staff user" do
      let!(:user) { log_in(:admin) }

      context "uneditable field" do
        let!(:user_field) { Fabricate(:user_field, editable: false) }

        it "allows staff to edit the field" do
          put :update, username: user.username, name: 'Jim Tom', user_fields: { user_field.id.to_s => 'happy' }
          expect(response).to be_success
          expect(user.user_fields[user_field.id.to_s]).to eq('happy')
        end
      end

    end

    context 'with authenticated user' do
      context 'with permission to update' do
        let!(:user) { log_in(:user) }

        it 'allows the update' do

          user2 = Fabricate(:user)
          user3 = Fabricate(:user)

          put :update,
                username: user.username,
                name: 'Jim Tom',
                custom_fields: {test: :it},
                muted_usernames: "#{user2.username},#{user3.username}"

          expect(response).to be_success

          user.reload

          expect(user.name).to eq 'Jim Tom'
          expect(user.custom_fields['test']).to eq 'it'
          expect(user.muted_users.pluck(:username).sort).to eq [user2.username,user3.username].sort

          put :update,
                username: user.username,
                muted_usernames: ""

          user.reload

          expect(user.muted_users.pluck(:username).sort).to be_empty

        end

        context 'a locale is chosen that differs from I18n.locale' do
          it "updates the user's locale" do
            I18n.stubs(:locale).returns('fr')

            put :update,
                username: user.username,
                locale: :fa_IR

            expect(User.find_by(username: user.username).locale).to eq('fa_IR')
          end

        end

        context "with user fields" do
          context "an editable field" do
            let!(:user_field) { Fabricate(:user_field) }
            let!(:optional_field) { Fabricate(:user_field, required: false ) }

            it "should update the user field" do
              put :update, username: user.username, name: 'Jim Tom', user_fields: { user_field.id.to_s => 'happy' }
              expect(response).to be_success
              expect(user.user_fields[user_field.id.to_s]).to eq 'happy'
            end

            it "cannot be updated to blank" do
              put :update, username: user.username, name: 'Jim Tom', user_fields: { user_field.id.to_s => '' }
              expect(response).not_to be_success
              expect(user.user_fields[user_field.id.to_s]).not_to eq('happy')
            end

            it "trims excessively large fields" do
              put :update, username: user.username, name: 'Jim Tom', user_fields: { user_field.id.to_s => ('x' * 3000) }
              expect(user.user_fields[user_field.id.to_s].size).to eq(UserField.max_length)
            end
          end

          context "uneditable field" do
            let!(:user_field) { Fabricate(:user_field, editable: false) }

            it "does not update the user field" do
              put :update, username: user.username, name: 'Jim Tom', user_fields: { user_field.id.to_s => 'happy' }
              expect(response).to be_success
              expect(user.user_fields[user_field.id.to_s]).to be_blank
            end
          end

        end

        it 'returns user JSON' do
          put :update, username: user.username

          json = JSON.parse(response.body)
          expect(json['user']['id']).to eq user.id
        end

      end

      context 'without permission to update' do
        it 'does not allow the update' do
          user = Fabricate(:user, name: 'Billy Bob')
          log_in_user(user)
          Guardian.any_instance.expects(:can_edit?).with(user).returns(false)

          put :update, username: user.username, name: 'Jim Tom'

          expect(response).to be_forbidden
          expect(user.reload.name).not_to eq 'Jim Tom'
        end
      end
    end
  end

  describe "badge_card" do
    let(:user) { Fabricate(:user) }
    let(:badge) { Fabricate(:badge) }
    let(:user_badge) { BadgeGranter.grant(badge, user) }

    it "sets the user's card image to the badge" do
      log_in_user user
      xhr :put, :update_card_badge, user_badge_id: user_badge.id, username: user.username
      expect(user.user_profile.reload.card_image_badge_id).to be_blank
      badge.update_attributes image: "wat.com/wat.jpg"

      xhr :put, :update_card_badge, user_badge_id: user_badge.id, username: user.username
      expect(user.user_profile.reload.card_image_badge_id).to eq(badge.id)

      # Can set to nothing
      xhr :put, :update_card_badge, username: user.username
      expect(user.user_profile.reload.card_image_badge_id).to be_blank
    end
  end

  describe "badge_title" do
    let(:user) { Fabricate(:user) }
    let(:badge) { Fabricate(:badge) }
    let(:user_badge) { BadgeGranter.grant(badge, user) }

    it "sets the user's title to the badge name if it is titleable" do
      log_in_user user
      xhr :put, :badge_title, user_badge_id: user_badge.id, username: user.username
      expect(user.reload.title).not_to eq(badge.name)
      badge.update_attributes allow_title: true
      xhr :put, :badge_title, user_badge_id: user_badge.id, username: user.username
      expect(user.reload.title).to eq(badge.name)
      expect(user.user_profile.badge_granted_title).to eq(true)

      user.title = "testing"
      user.save
      user.user_profile.reload
      expect(user.user_profile.badge_granted_title).to eq(false)

    end
  end

  describe "search_users" do

    let(:topic) { Fabricate :topic }
    let(:user)  { Fabricate :user, username: "joecabot", name: "Lawrence Tierney" }

    before do
      SearchIndexer.enable
      Fabricate :post, user: user, topic: topic
    end

    it "searches when provided the term only" do
      xhr :post, :search_users, term: user.name.split(" ").last
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["users"].map { |u| u["username"] }).to include(user.username)
    end

    it "searches when provided the topic only" do
      xhr :post, :search_users, topic_id: topic.id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["users"].map { |u| u["username"] }).to include(user.username)
    end

    it "searches when provided the term and topic" do
      xhr :post, :search_users, term: user.name.split(" ").last, topic_id: topic.id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["users"].map { |u| u["username"] }).to include(user.username)
    end

    it "searches only for users who have access to private topic" do
      privileged_user = Fabricate(:user, trust_level: 4, username: "joecabit", name: "Lawrence Tierney")
      privileged_group = Fabricate(:group)
      privileged_group.add(privileged_user)
      privileged_group.save

      category = Fabricate(:category)
      category.set_permissions(privileged_group => :readonly)
      category.save

      private_topic = Fabricate(:topic, category: category)

      xhr :post, :search_users, term: user.name.split(" ").last, topic_id: private_topic.id, topic_allowed_users: "true"
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["users"].map { |u| u["username"] }).to_not include(user.username)
      expect(json["users"].map { |u| u["username"] }).to include(privileged_user.username)
    end

    context "when `enable_names` is true" do
      before do
        SiteSetting.enable_names = true
      end

      it "returns names" do
        xhr :post, :search_users, term: user.name
        json = JSON.parse(response.body)
        expect(json["users"].map { |u| u["name"] }).to include(user.name)
      end
    end

    context "when `enable_names` is false" do
      before do
        SiteSetting.enable_names = false
      end

      it "returns names" do
        xhr :post, :search_users, term: user.name
        json = JSON.parse(response.body)
        expect(json["users"].map { |u| u["name"] }).not_to include(user.name)
      end
    end

  end

  describe 'send_activation_email' do
    context 'for an existing user' do
      let(:user) { Fabricate(:user, active: false) }

      context 'for an activated account with email confirmed' do
        it 'fails' do
          active_user = Fabricate(:user, active: true)
          email_token = active_user.email_tokens.create(email: active_user.email).token
          EmailToken.confirm(email_token)
          session[SessionController::ACTIVATE_USER_KEY] = active_user.id
          xhr :post, :send_activation_email, username: active_user.username

          expect(response.status).to eq(409)

          expect(JSON.parse(response.body)['errors']).to include(I18n.t(
            'activation.activated'
          ))

          expect(session[SessionController::ACTIVATE_USER_KEY]).to eq(nil)
        end
      end

      context 'for an activated account with unconfirmed email' do
        it 'should send an email' do
          unconfirmed_email_user = Fabricate(:user, active: true)
          unconfirmed_email_user.email_tokens.create(email: unconfirmed_email_user.email)
          session[SessionController::ACTIVATE_USER_KEY] = unconfirmed_email_user.id
          Jobs.expects(:enqueue).with(:critical_user_email, has_entries(type: :signup))
          xhr :post, :send_activation_email, username: unconfirmed_email_user.username

          expect(response.status).to eq(200)

          expect(session[SessionController::ACTIVATE_USER_KEY]).to eq(nil)
        end
      end

      describe 'when user does not have a valid session' do
        it 'should not be valid' do
          user = Fabricate(:user)
          xhr :post, :send_activation_email, username: user.username
          expect(response.status).to eq(403)
        end

        it 'should allow staff regardless' do
          log_in :admin
          user = Fabricate(:user, active: false)
          xhr :post, :send_activation_email, username: user.username
          expect(response.status).to eq(200)
        end
      end

      context 'with a valid email_token' do
        it 'should send the activation email' do
          session[SessionController::ACTIVATE_USER_KEY] = user.id
          Jobs.expects(:enqueue).with(:critical_user_email, has_entries(type: :signup))
          xhr :post, :send_activation_email, username: user.username

          expect(session[SessionController::ACTIVATE_USER_KEY]).to eq(nil)
        end
      end

      context 'without an existing email_token' do
        before do
          user.email_tokens.each {|t| t.destroy}
          user.reload
        end

        it 'should generate a new token' do
          expect {
            session[SessionController::ACTIVATE_USER_KEY] = user.id
            xhr :post, :send_activation_email, username: user.username
          }.to change{ user.email_tokens(true).count }.by(1)
        end

        it 'should send an email' do
          session[SessionController::ACTIVATE_USER_KEY] = user.id
          Jobs.expects(:enqueue).with(:critical_user_email, has_entries(type: :signup))
          xhr :post, :send_activation_email, username: user.username

          expect(session[SessionController::ACTIVATE_USER_KEY]).to eq(nil)
        end
      end
    end

    context 'when username does not exist' do
      it 'should not send an email' do
        Jobs.expects(:enqueue).never
        xhr :post, :send_activation_email, username: 'nopenopenopenope'
      end
    end
  end

  describe '.pick_avatar' do

    it 'raises an error when not logged in' do
      expect {
        xhr :put, :pick_avatar, username: 'asdf', avatar_id: 1, type: "custom"
      }.to raise_error(Discourse::NotLoggedIn)
    end

    context 'while logged in' do

      let!(:user) { log_in }
      let(:upload) { Fabricate(:upload) }

      it "raises an error when you don't have permission to toggle the avatar" do
        another_user = Fabricate(:user)
        xhr :put, :pick_avatar, username: another_user.username, upload_id: upload.id, type: "custom"
        expect(response).to be_forbidden
      end

      it "raises an error when sso_overrides_avatar is disabled" do
        SiteSetting.sso_overrides_avatar = true
        xhr :put, :pick_avatar, username: user.username, upload_id: upload.id, type: "custom"
        expect(response).to_not be_success
      end

      it "raises an error when selecting the custom/uploaded avatar and allow_uploaded_avatars is disabled" do
        SiteSetting.allow_uploaded_avatars = false
        xhr :put, :pick_avatar, username: user.username, upload_id: upload.id, type: "custom"
        expect(response).to_not be_success
      end

      it 'can successfully pick the system avatar' do
        xhr :put, :pick_avatar, username: user.username
        expect(response).to be_success
        expect(user.reload.uploaded_avatar_id).to eq(nil)
      end

      it 'can successfully pick a gravatar' do
        xhr :put, :pick_avatar, username: user.username, upload_id: upload.id, type: "gravatar"
        expect(response).to be_success
        expect(user.reload.uploaded_avatar_id).to eq(upload.id)
        expect(user.user_avatar.reload.gravatar_upload_id).to eq(upload.id)
      end

      it 'can successfully pick a custom avatar' do
        xhr :put, :pick_avatar, username: user.username, upload_id: upload.id, type: "custom"
        expect(response).to be_success
        expect(user.reload.uploaded_avatar_id).to eq(upload.id)
        expect(user.user_avatar.reload.custom_upload_id).to eq(upload.id)
      end

    end

  end

  describe '.destroy_user_image' do

    it 'raises an error when not logged in' do
      expect { xhr :delete, :destroy_user_image, type: 'profile_background', username: 'asdf' }.to raise_error(Discourse::NotLoggedIn)
    end

    context 'while logged in' do

      let!(:user) { log_in }

      it 'raises an error when you don\'t have permission to clear the profile background' do
        Guardian.any_instance.expects(:can_edit?).with(user).returns(false)
        xhr :delete, :destroy_user_image, username: user.username, type: 'profile_background'
        expect(response).to be_forbidden
      end

      it "requires the `type` param" do
        expect { xhr :delete, :destroy_user_image, username: user.username }.to raise_error(ActionController::ParameterMissing)
      end

      it "only allows certain `types`" do
        expect { xhr :delete, :destroy_user_image, username: user.username, type: 'wat' }.to raise_error(Discourse::InvalidParameters)
      end

      it 'can clear the profile background' do
        xhr :delete, :destroy_user_image, type: 'profile_background', username: user.username
        expect(user.reload.user_profile.profile_background).to eq("")
        expect(response).to be_success
      end

    end
  end

  describe '.destroy' do
    it 'raises an error when not logged in' do
      expect { xhr :delete, :destroy, username: 'nobody' }.to raise_error(Discourse::NotLoggedIn)
    end

    context 'while logged in' do
      let!(:user) { log_in }

      it 'raises an error when you cannot delete your account' do
        Guardian.any_instance.stubs(:can_delete_user?).returns(false)
        UserDestroyer.any_instance.expects(:destroy).never
        xhr :delete, :destroy, username: user.username
        expect(response).to be_forbidden
      end

      it "raises an error when you try to delete someone else's account" do
        UserDestroyer.any_instance.expects(:destroy).never
        xhr :delete, :destroy, username: Fabricate(:user).username
        expect(response).to be_forbidden
      end

      it "deletes your account when you're allowed to" do
        Guardian.any_instance.stubs(:can_delete_user?).returns(true)
        UserDestroyer.any_instance.expects(:destroy).with(user, anything).returns(user)
        xhr :delete, :destroy, username: user.username
        expect(response).to be_success
      end
    end
  end

  describe '.my_redirect' do

    it "redirects if the user is not logged in" do
      get :my_redirect, path: "wat"
      expect(response).not_to be_success
      expect(response).to be_redirect
    end

    context "when the user is logged in" do
      let!(:user) { log_in }

      it "will not redirect to an invalid path" do
        get :my_redirect, path: "wat/..password.txt"
        expect(response).not_to be_redirect
      end

      it "will redirect to an valid path" do
        get :my_redirect, path: "preferences"
        expect(response).to be_redirect
      end

      it "permits forward slashes" do
        get :my_redirect, path: "activity/posts"
        expect(response).to be_redirect
      end
    end
  end

  describe '.check_emails' do

    it 'raises an error when not logged in' do
      expect { xhr :put, :check_emails, username: 'zogstrip' }.to raise_error(Discourse::NotLoggedIn)
    end

    context 'while logged in' do
      let!(:user) { log_in }

      it "raises an error when you aren't allowed to check emails" do
        Guardian.any_instance.expects(:can_check_emails?).returns(false)
        xhr :put, :check_emails, username: Fabricate(:user).username
        expect(response).to be_forbidden
      end

      it "returns both email and associated_accounts when you're allowed to see them" do
        Guardian.any_instance.expects(:can_check_emails?).returns(true)
        xhr :put, :check_emails, username: Fabricate(:user).username
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json["email"]).to be_present
        expect(json["associated_accounts"]).to be_present
      end

      it "works on inactive users" do
        inactive_user = Fabricate(:user, active: false)
        Guardian.any_instance.expects(:can_check_emails?).returns(true)
        xhr :put, :check_emails, username: inactive_user.username
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json["email"]).to be_present
        expect(json["associated_accounts"]).to be_present
      end

    end

  end

  describe ".is_local_username" do

    let(:user) { Fabricate(:user) }
    let(:group) { Fabricate(:group, name: "Discourse") }
    let(:topic) { Fabricate(:topic) }
    let(:allowed_user) { Fabricate(:user) }
    let(:private_topic) { Fabricate(:private_message_topic, user: allowed_user) }

    it "finds the user" do
      xhr :get, :is_local_username, username: user.username
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["valid"][0]).to eq(user.username)
    end

    it "finds the group" do
      xhr :get, :is_local_username, username: group.name
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["valid_groups"][0]).to eq(group.name)
    end

    it "supports multiples usernames" do
      xhr :get, :is_local_username, usernames: [user.username, "system"]
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["valid"].size).to eq(2)
    end

    it "never includes staged accounts" do
      staged = Fabricate(:user, staged: true)
      xhr :get, :is_local_username, usernames: [staged.username]
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["valid"].size).to eq(0)
    end

    it "returns user who cannot see topic" do
      Guardian.any_instance.expects(:can_see?).with(topic).returns(false)
      xhr :get, :is_local_username, usernames: [user.username], topic_id: topic.id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["cannot_see"].size).to eq(1)
    end

    it "never returns a user who can see the topic" do
      Guardian.any_instance.expects(:can_see?).with(topic).returns(true)
      xhr :get, :is_local_username, usernames: [user.username], topic_id: topic.id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["cannot_see"].size).to eq(0)
    end

    it "returns user who cannot see a private topic" do
      Guardian.any_instance.expects(:can_see?).with(private_topic).returns(false)
      xhr :get, :is_local_username, usernames: [user.username], topic_id: private_topic.id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["cannot_see"].size).to eq(1)
    end

    it "never returns a user who can see the topic" do
      Guardian.any_instance.expects(:can_see?).with(private_topic).returns(true)
      xhr :get, :is_local_username, usernames: [allowed_user.username], topic_id: private_topic.id
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["cannot_see"].size).to eq(0)
    end

  end

  describe '.topic_tracking_state' do
    let(:user){Fabricate(:user)}

    context 'anon' do
      it "raises an error on anon for topic_tracking_state" do
        expect{
          xhr :get, :topic_tracking_state, username: user.username, format: :json
        }.to raise_error(Discourse::NotLoggedIn)
      end
    end

    context 'logged on' do
      it "detects new topic" do
        log_in_user(user)

        topic = Fabricate(:topic)
        xhr :get, :topic_tracking_state, username: user.username, format: :json

        states = JSON.parse(response.body)

        expect(states[0]["topic_id"]).to eq(topic.id)
      end
    end
  end

  describe '.summary' do

    it "generates summary info" do
      user = Fabricate(:user)
      create_post(user: user)

      xhr :get, :summary, username: user.username_lower
      expect(response).to be_success
      json = JSON.parse(response.body)

      expect(json["user_summary"]["topic_count"]).to eq(1)
      expect(json["user_summary"]["post_count"]).to eq(1)
    end
  end


  describe ".confirm_admin" do
    it "fails without a valid token" do
      expect {
        get :confirm_admin, token: 'invalid-token'
      }.to raise_error(ActionController::UrlGenerationError)
    end

    it "fails with a missing token" do
      get :confirm_admin, token: 'a0a0a0a0a0'
      expect(response).to_not be_success
    end

    it "succeeds with a valid code as anonymous" do
      user = Fabricate(:user)
      ac = AdminConfirmation.new(user, Fabricate(:admin))
      ac.create_confirmation
      get :confirm_admin, token: ac.token
      expect(response).to be_success

      user.reload
      expect(user.admin?).to eq(false)
    end

    it "succeeds with a valid code when logged in as that user" do
      admin = log_in(:admin)
      user = Fabricate(:user)

      ac = AdminConfirmation.new(user, admin)
      ac.create_confirmation
      get :confirm_admin, token: ac.token
      expect(response).to be_success

      user.reload
      expect(user.admin?).to eq(false)
    end

    it "fails if you're logged in as a different account" do
      log_in(:admin)
      user = Fabricate(:user)

      ac = AdminConfirmation.new(user, Fabricate(:admin))
      ac.create_confirmation
      get :confirm_admin, token: ac.token
      expect(response).to_not be_success

      user.reload
      expect(user.admin?).to eq(false)
    end

    describe "post" do
      it "gives the user admin access when POSTed" do
        user = Fabricate(:user)
        ac = AdminConfirmation.new(user, Fabricate(:admin))
        ac.create_confirmation
        post :confirm_admin, token: ac.token
        expect(response).to be_success

        user.reload
        expect(user.admin?).to eq(true)
      end
    end

  end


  describe '.update_activation_email' do

    it "raises an error with an invalid username" do
      xhr :put, :update_activation_email, {
        username: 'eviltrout',
        password: 'invalid-password',
        email: 'updatedemail@example.com'
      }
      expect(response).to_not be_success
    end

    it "raises an error with an invalid password" do
      xhr :put, :update_activation_email, {
        username: Fabricate(:inactive_user).username,
        password: 'invalid-password',
        email: 'updatedemail@example.com'
      }
      expect(response).to_not be_success
    end

    it "raises an error for an active user" do
      xhr :put, :update_activation_email, {
        username: Fabricate(:walter_white).username,
        password: 'letscook',
        email: 'updatedemail@example.com'
      }
      expect(response).to_not be_success
    end

    it "raises an error when logged in" do
      log_in(:moderator)

      xhr :put, :update_activation_email, {
        username: Fabricate(:inactive_user).username,
        password: 'qwerqwer123',
        email: 'updatedemail@example.com'
      }
      expect(response).to_not be_success
    end

    it "raises an error when the new email is taken" do
      user = Fabricate(:user)

      xhr :put, :update_activation_email, {
        username: Fabricate(:inactive_user).username,
        password: 'qwerqwer123',
        email: user.email
      }
      expect(response).to_not be_success
    end

    it "can be updated" do
      user = Fabricate(:inactive_user)
      token = user.email_tokens.first

      xhr :put, :update_activation_email, {
        username: user.username,
        password: 'qwerqwer123',
        email: 'updatedemail@example.com'
      }

      expect(response).to be_success

      user.reload
      expect(user.email).to eq('updatedemail@example.com')
      expect(user.email_tokens.where(email: 'updatedemail@example.com', expired: false)).to be_present

      token.reload
      expect(token.expired?).to eq(true)
    end
  end

end
