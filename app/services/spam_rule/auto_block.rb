class SpamRule::AutoBlock

  def initialize(user)
    @user = user
  end

  def self.block?(user)
    self.new(user).block?
  end

  def self.punish!(user)
    self.new(user).block_user
  end

  def perform
    block_user if block?
  end

  def block?
    return true if @user.blocked?
    return false if @user.staged?
    return false if @user.has_trust_level?(TrustLevel[1])

    if SiteSetting.num_spam_flags_to_block_new_user > 0 and
        SiteSetting.num_users_to_block_new_user > 0 and
        num_spam_flags_against_user >= SiteSetting.num_spam_flags_to_block_new_user and
        num_users_who_flagged_spam_against_user >= SiteSetting.num_users_to_block_new_user
      return true
    end

    if SiteSetting.num_tl3_flags_to_block_new_user > 0 and
        SiteSetting.num_tl3_users_to_block_new_user > 0 and
        num_tl3_flags_against_user >= SiteSetting.num_tl3_flags_to_block_new_user and
        num_tl3_users_who_flagged >= SiteSetting.num_tl3_users_to_block_new_user
      return true
    end

    false
  end

  def num_spam_flags_against_user
    Post.where(user_id: @user.id).sum(:spam_count)
  end

  def num_users_who_flagged_spam_against_user
    post_ids = Post.where('user_id = ? and spam_count > 0', @user.id).pluck(:id)
    return 0 if post_ids.empty?
    PostAction.spam_flags.where(post_id: post_ids).uniq.pluck(:user_id).size
  end

  def num_tl3_flags_against_user
    if flagged_post_ids.empty?
      0
    else
      PostAction.where(post_id: flagged_post_ids).joins(:user).where('users.trust_level >= ?', 3).count
    end
  end

  def num_tl3_users_who_flagged
    if flagged_post_ids.empty?
      0
    else
      PostAction.where(post_id: flagged_post_ids).joins(:user).where('users.trust_level >= ?', 3).pluck(:user_id).uniq.size
    end
  end

  def flagged_post_ids
    Post.where(user_id: @user.id)
        .where('spam_count > ? OR off_topic_count > ? OR inappropriate_count > ?', 0, 0, 0)
        .pluck(:id)
  end

  def block_user
    Post.transaction do
      if UserBlocker.block(@user, Discourse.system_user, message: :too_many_spam_flags) && SiteSetting.notify_mods_when_user_blocked
        GroupMessage.create(Group[:moderators].name, :user_automatically_blocked, {user: @user, limit_once_per: false})
      end
    end
  end
end
