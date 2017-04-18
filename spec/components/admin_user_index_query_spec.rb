require 'rails_helper'
require_dependency 'admin_user_index_query'

describe AdminUserIndexQuery do
  def real_users_count(query)
    query.find_users_query.where('users.id > 0').count
  end

  describe "sql order" do
    it "has default" do
      query = ::AdminUserIndexQuery.new({})
      expect(query.find_users_query.to_sql).to match("created_at DESC")
    end

    it "has active order" do
      query = ::AdminUserIndexQuery.new({ query: "active" })
      expect(query.find_users_query.to_sql).to match("last_seen_at")
    end

    it "can't be injected" do
      query = ::AdminUserIndexQuery.new({ order: "wat, no" })
      expect(query.find_users_query.to_sql).not_to match("wat, no")
    end

    it "allows custom ordering" do
      query = ::AdminUserIndexQuery.new({ order: "trust_level" })
      expect(query.find_users_query.to_sql).to match("trust_level DESC")
    end
    
    it "allows custom ordering asc" do
      query = ::AdminUserIndexQuery.new({ order: "trust_level", ascending: true })
      expect(query.find_users_query.to_sql).to match("trust_level ASC" )
    end

    it "allows custom ordering for stats wtih default direction" do
      query = ::AdminUserIndexQuery.new({ order: "topics_viewed" })
      expect(query.find_users_query.to_sql).to match("topics_entered DESC")
    end

    it "allows custom ordering and direction for stats" do
      query = ::AdminUserIndexQuery.new({ order: "topics_viewed", ascending: true })
      expect(query.find_users_query.to_sql).to match("topics_entered ASC")
    end
  end

  describe "no users with trust level" do

    TrustLevel.levels.each do |key, value|
      it "#{key} returns no records" do
        query = ::AdminUserIndexQuery.new({ query: key.to_s })
        expect(real_users_count(query)).to eq(0)
      end
    end

  end

  describe "users with trust level" do

    TrustLevel.levels.each do |key, value|
      it "finds user with trust #{key}" do
        Fabricate(:user, trust_level: TrustLevel.levels[key])
        query = ::AdminUserIndexQuery.new({ query: key.to_s })
        expect(real_users_count(query)).to eq(1)
      end
    end

  end

  describe "with a pending user" do

    let!(:user) { Fabricate(:user, approved: false) }

    it "finds the unapproved user" do
      query = ::AdminUserIndexQuery.new({ query: 'pending' })
      expect(query.find_users.count).to eq(1)
    end

    context 'and a suspended pending user' do
      let!(:suspended_user) { Fabricate(:user, approved: false, suspended_at: 1.hour.ago, suspended_till: 20.years.from_now) }
      it "doesn't return the suspended user" do
        query = ::AdminUserIndexQuery.new({ query: 'pending' })
        expect(query.find_users.count).to eq(1)
      end
    end

  end

  describe "correct order with nil values" do
    before(:each) do
      Fabricate(:user, email: "test2@example.com", last_emailed_at: 1.hour.ago)
    end

    it "shows nil values first with asc" do
      users = ::AdminUserIndexQuery.new({ order: "last_emailed", ascending: true }).find_users

      expect(users.count).to eq(2)
      expect(users.first.username).to eq("system")
      expect(users.first.last_emailed_at).to eq(nil)
    end

    it "shows nil values last with desc" do
      users = ::AdminUserIndexQuery.new({ order: "last_emailed"}).find_users

      expect(users.count).to eq(2)
      expect(users.first.last_emailed_at).to_not eq(nil)
    end

  end

  describe "with an admin user" do

    let!(:user) { Fabricate(:user, admin: true) }

    it "finds the admin" do
      query = ::AdminUserIndexQuery.new({ query: 'admins' })
      expect(real_users_count(query)).to eq(1)
    end

  end

  describe "with a moderator" do

    let!(:user) { Fabricate(:user, moderator: true) }

    it "finds the moderator" do
      query = ::AdminUserIndexQuery.new({ query: 'moderators' })
      expect(real_users_count(query)).to eq(1)
    end

  end

  describe "with a blocked user" do

    let!(:user) { Fabricate(:user, blocked: true) }

    it "finds the blocked user" do
      query = ::AdminUserIndexQuery.new({ query: 'blocked' })
      expect(query.find_users.count).to eq(1)
    end

  end

  describe "filtering" do

    context "by email fragment" do

      before(:each) { Fabricate(:user, email: "test1@example.com") }

      it "matches the email" do
        query = ::AdminUserIndexQuery.new({ filter: " est1" })
        expect(query.find_users.count()).to eq(1)
      end

      it "matches the email using any case" do
        query = ::AdminUserIndexQuery.new({ filter: "Test1\t" })
        expect(query.find_users.count()).to eq(1)
      end

    end

    context "by username fragment" do

      before(:each) { Fabricate(:user, username: "test_user_1") }

      it "matches the username" do
        query = ::AdminUserIndexQuery.new({ filter: "user\n" })
        expect(query.find_users.count).to eq(1)
      end

      it "matches the username using any case" do
        query = ::AdminUserIndexQuery.new({ filter: "\r\nUser" })
        expect(query.find_users.count).to eq(1)
      end
    end

    context "by ip address fragment" do

      let!(:user) { Fabricate(:user, ip_address: "117.207.94.9") }

      it "matches the ip address" do
        query = ::AdminUserIndexQuery.new({ filter: " 117.207.94.9 " })
        expect(query.find_users.count()).to eq(1)
      end

    end

  end
end
