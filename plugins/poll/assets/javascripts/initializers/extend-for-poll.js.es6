import { withPluginApi } from 'discourse/lib/plugin-api';
import { observes } from "ember-addons/ember-computed-decorators";
import { getRegister } from 'discourse-common/lib/get-owner';
import WidgetGlue from 'discourse/widgets/glue';

function initializePolls(api) {
  const register = getRegister(api);

  const TopicController = api.container.lookupFactory('controller:topic');
  TopicController.reopen({
    subscribe(){
      this._super();
      this.messageBus.subscribe("/polls/" + this.get("model.id"), msg => {
        const post = this.get('model.postStream').findLoadedPost(msg.post_id);
        if (post) {
          post.set('polls', msg.polls);
        }
      });
    },
    unsubscribe(){
      this.messageBus.unsubscribe('/polls/*');
      this._super();
    }
  });

  const Post = api.container.lookupFactory('model:post');
  Post.reopen({
    _polls: null,
    pollsObject: null,

    // we need a proper ember object so it is bindable
    @observes("polls")
    pollsChanged() {
      const polls = this.get("polls");
      if (polls) {
        this._polls = this._polls || {};
        _.map(polls, (v,k) => {
          const existing = this._polls[k];
          if (existing) {
            this._polls[k].setProperties(v);
          } else {
            this._polls[k] = Em.Object.create(v);
          }
        });
        this.set("pollsObject", this._polls);
        _glued.forEach(g => g.queueRerender());
      }
    }
  });

  const _glued = [];
  function attachPolls($elem, helper) {
    const $polls = $('.poll', $elem);
    if (!$polls.length) { return; }

    const post = helper.getModel();
    api.preventCloak(post.id);
    const votes = post.get('polls_votes') || {};

    post.pollsChanged();

    const polls = post.get("pollsObject");
    if (!polls) { return; }

    $polls.each((idx, pollElem) => {
      const $poll = $(pollElem);
      const pollName = $poll.data("poll-name");
      const poll = polls[pollName];
      if (poll) {
        const isMultiple = poll.get('type') === 'multiple';

        const glue = new WidgetGlue('discourse-poll', register, {
          id: `${pollName}-${post.id}`,
          post,
          poll,
          vote: votes[pollName] || [],
          isMultiple,
        });
        glue.appendTo(pollElem);
        _glued.push(glue);
      }
    });
  }

  function cleanUpPolls() {
    _glued.forEach(g => g.cleanUp());
  }

  api.includePostAttributes("polls", "polls_votes");
  api.decorateCooked(attachPolls, { onlyStream: true });
  api.cleanupStream(cleanUpPolls);
}

export default {
  name: "extend-for-poll",

  initialize() {
    withPluginApi('0.1', initializePolls);
  }
};
