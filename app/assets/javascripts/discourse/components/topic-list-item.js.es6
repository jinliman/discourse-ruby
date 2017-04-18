import DiscourseURL from 'discourse/lib/url';
import computed from 'ember-addons/ember-computed-decorators';
import { bufferedRender } from 'discourse-common/lib/buffered-render';
import { findRawTemplate } from 'discourse/lib/raw-templates';
import { wantsNewWindow } from 'discourse/lib/intercept-click';

export function showEntrance(e) {
  let target = $(e.target);

  if (target.hasClass('posts-map') || target.parents('.posts-map').length > 0) {
    if (target.prop('tagName') !== 'A') {
      target = target.find('a');
      if (target.length===0) {
        target = target.end();
      }
    }

    this.appEvents.trigger('topic-entrance:show', { topic: this.get('topic'), position: target.offset() });
    return false;
  }
}

export default Ember.Component.extend(bufferedRender({
  rerenderTriggers: ['bulkSelectEnabled', 'topic.pinned'],
  tagName: 'tr',
  classNameBindings: [':topic-list-item', 'unboundClassNames'],
  attributeBindings: ['data-topic-id'],
  'data-topic-id': Em.computed.alias('topic.id'),

  actions: {
    toggleBookmark() {
      this.get('topic').toggleBookmark().finally(() => this.rerenderBuffer());
    }
  },

  buildBuffer(buffer) {
    const template = findRawTemplate('list/topic-list-item');
    if (template) {
      buffer.push(template(this));
    }
  },

  @computed('topic', 'lastVisitedTopic')
  unboundClassNames(topic, lastVisitedTopic) {
    let classes = [];

    if (topic.get('category')) {
      classes.push("category-" + topic.get('category.fullSlug'));
    }

    if (topic.get('hasExcerpt')) {
      classes.push('has-excerpt');
    }

    _.each(['liked', 'archived', 'bookmarked'],function(name) {
      if (topic.get(name)) {
        classes.push(name);
      }
    });

    if (topic === lastVisitedTopic) {
      classes.push('last-visit');
    }

    return classes.join(' ');
  },

  titleColSpan: function() {
    return (!this.get('hideCategory') &&
             this.get('topic.isPinnedUncategorized') ? 2 : 1);
  }.property("topic.isPinnedUncategorized"),


  hasLikes: function() {
    return this.get('topic.like_count') > 0;
  },

  hasOpLikes: function() {
    return this.get('topic.op_like_count') > 0;
  },

  expandPinned: function() {
    const pinned = this.get('topic.pinned');
    if (!pinned) {
      return false;
    }

    if (this.site.mobileView) {
      if (!this.siteSettings.show_pinned_excerpt_mobile) {
        return false;
      }
    } else {
      if (!this.siteSettings.show_pinned_excerpt_desktop) {
        return false;
      }
    }

    if (this.get('expandGloballyPinned') && this.get('topic.pinned_globally')) {
      return true;
    }

    if (this.get('expandAllPinned')) {
      return true;
    }

    return false;
  }.property(),

  click(e) {
    const result = showEntrance.call(this, e);
    if (result === false) { return result; }

    const topic = this.get('topic');
    const target = $(e.target);
    if (target.hasClass('bulk-select')) {
      const selected = this.get('selected');

      if (target.is(':checked')) {
        selected.addObject(topic);
      } else {
        selected.removeObject(topic);
      }
    }

    if (target.hasClass('raw-topic-link')) {
       if (wantsNewWindow(e)) { return true; }

      this.appEvents.trigger('header:update-topic', topic);
      DiscourseURL.routeTo(target.attr('href'));
      return false;
    }

    if (target.closest('a.topic-status').length === 1) {
      this.get('topic').togglePinnedForUser();
      return false;
    }
  },

  highlight(opts = { isLastViewedTopic: false }) {
    const $topic = this.$();
    $topic
      .addClass('highlighted')
      .attr('data-islastviewedtopic', opts.isLastViewedTopic);

    $topic.on('animationend', () => $topic.removeClass('highlighted'));
  },

  _highlightIfNeeded: function() {
    // highlight the last topic viewed
    if (this.session.get('lastTopicIdViewed') === this.get('topic.id')) {
      this.session.set('lastTopicIdViewed', null);
      this.highlight({ isLastViewedTopic: true });
    } else if (this.get('topic.highlight')) {
      // highlight new topics that have been loaded from the server or the one we just created
      this.set('topic.highlight', false);
      this.highlight();
    }
  }.on('didInsertElement')

}));
