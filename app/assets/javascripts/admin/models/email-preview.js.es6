import { ajax } from 'discourse/lib/ajax';
const EmailPreview = Discourse.Model.extend({});

EmailPreview.reopenClass({
  findDigest: function(lastSeenAt, username) {

    if (Em.isEmpty(lastSeenAt)) {
      lastSeenAt = this.oneWeekAgo();
    }

    if (Em.isEmpty(username)) {
      username = Discourse.User.current().username;
    }

    return ajax("/admin/email/preview-digest.json", {
      data: { last_seen_at: lastSeenAt, username: username }
    }).then(function (result) {
      return EmailPreview.create(result);
    });
  },

  sendDigest: function(lastSeenAt, username, email) {
    if (Em.isEmpty(lastSeenAt)) {
      lastSeenAt = this.oneWeekAgo();
    }

    if (Em.isEmpty(username)) {
      username = Discourse.User.current().username;
    }

    return ajax("/admin/email/send-digest.json", {
      data: { last_seen_at: lastSeenAt, username: username, email: email }
    });
  },

  oneWeekAgo() {
    const en = moment().locale('en');
    return en.subtract(7, 'days').format('YYYY-MM-DD');
  }
});

export default EmailPreview;
