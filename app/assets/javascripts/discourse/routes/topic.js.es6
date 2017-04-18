import DiscourseURL from 'discourse/lib/url';

let isTransitioning = false,
    scheduledReplace = null,
    lastScrollPos = null;

const SCROLL_DELAY = 500;

import showModal from 'discourse/lib/show-modal';

const TopicRoute = Discourse.Route.extend({
  redirect() { return this.redirectIfLoginRequired(); },

  queryParams: {
    filter: { replace: true },
    username_filters: { replace: true },
  },

  titleToken() {
    const model = this.modelFor('topic');
    if (model) {
      const result = model.get('unicode_title') ? model.get('unicode_title') : model.get('title'),
            cat = model.get('category');

      // Only display uncategorized in the title tag if it was renamed
      if (cat && !(cat.get('isUncategorizedCategory') && cat.get('name').toLowerCase() === "uncategorized")) {
        let catName = cat.get('name');

        const parentCategory = cat.get('parentCategory');
        if (parentCategory) {
          catName = parentCategory.get('name') + " / " + catName;
        }

        return [result, catName];
      }
      return result;
    }
  },

  actions: {

    showFlags(model) {
      showModal('flag', { model });
      this.controllerFor('flag').setProperties({ selected: null, flagTopic: false });
    },

    showFlagTopic() {
      const model = this.modelFor('topic');
      showModal('flag',  { model });
      this.controllerFor('flag').setProperties({ selected: null, flagTopic: true });
    },

    showTopicStatusUpdate() {
      const model = this.modelFor('topic');
      model.set('topic_status_update', Ember.Object.create(model.get('topic_status_update')));
      showModal('edit-topic-status-update', { model });
      this.controllerFor('modal').set('modalClass', 'topic-close-modal');
    },

    showChangeTimestamp() {
      showModal('change-timestamp', { model: this.modelFor('topic'), title: 'topic.change_timestamp.title' });
    },

    showFeatureTopic() {
      showModal('featureTopic', { model: this.modelFor('topic'), title: 'topic.feature_topic.title' });
      this.controllerFor('modal').set('modalClass', 'feature-topic-modal');
      this.controllerFor('feature_topic').reset();
    },

    showInvite() {
      showModal('invite', { model: this.modelFor('topic') });
      this.controllerFor('invite').reset();
    },

    showHistory(model) {
      showModal('history', { model });
      const historyController = this.controllerFor('history');

      historyController.refresh(model.get("id"), "latest");
      historyController.set('post', model);
      historyController.set('topicController', this.controllerFor('topic'));

      this.controllerFor('modal').set('modalClass', 'history-modal');
    },

    showRawEmail(model) {
      showModal('raw-email', { model });
      this.controllerFor('raw_email').loadRawEmail(model.get("id"));
    },

    mergeTopic() {
      showModal('merge-topic', { model: this.modelFor('topic'), title: 'topic.merge_topic.title' });
    },

    splitTopic() {
      showModal('split-topic', { model: this.modelFor('topic') });
    },

    changeOwner() {
      showModal('change-owner', { model: this.modelFor('topic'), title: 'topic.change_owner.title' });
    },

    // Use replaceState to update the URL once it changes
    postChangedRoute(currentPost) {
      // do nothing if we are transitioning to another route
      if (isTransitioning || TopicRoute.disableReplaceState) { return; }

      const topic = this.modelFor('topic');
      if (topic && currentPost) {
        let postUrl = topic.get('url');
        if (currentPost > 1) { postUrl += "/" + currentPost; }

        Em.run.cancel(scheduledReplace);
        lastScrollPos = parseInt($(document).scrollTop(), 10);
        scheduledReplace = Em.run.later(this, '_replaceUnlessScrolling', postUrl, SCROLL_DELAY);
      }
    },

    didTransition() {
      this.controllerFor("topic")._showFooter();
      return true;
    },

    willTransition() {
      this._super();
      Em.run.cancel(scheduledReplace);
      isTransitioning = true;
      return true;
    }
  },

  // replaceState can be very slow on Android Chrome. This function debounces replaceState
  // within a topic until scrolling stops
  _replaceUnlessScrolling(url) {
    const currentPos = parseInt($(document).scrollTop(), 10);
    if (currentPos === lastScrollPos) {
      DiscourseURL.replaceState(url);
      return;
    }
    lastScrollPos = currentPos;
    scheduledReplace = Em.run.later(this, '_replaceUnlessScrolling', url, SCROLL_DELAY);
  },

  setupParams(topic, params) {
    const postStream = topic.get('postStream');
    postStream.set('summary', Em.get(params, 'filter') === 'summary');

    const usernames = Em.get(params, 'username_filters'),
        userFilters = postStream.get('userFilters');

    userFilters.clear();
    if (!Em.isEmpty(usernames) && usernames !== 'undefined') {
      userFilters.addObjects(usernames.split(','));
    }

    return topic;
  },

  model(params, transition) {
    const queryParams = transition.queryParams;

    let topic = this.modelFor('topic');
    if (topic && (topic.get('id') === parseInt(params.id, 10))) {
      this.setupParams(topic, queryParams);
      return topic;
    } else {
      topic = this.store.createRecord('topic', _.omit(params, 'username_filters', 'filter'));
      return this.setupParams(topic, queryParams);
    }
  },

  activate() {
    this._super();
    isTransitioning = false;

    const topic = this.modelFor('topic');
    this.session.set('lastTopicIdViewed', parseInt(topic.get('id'), 10));
  },

  deactivate() {
    this._super();

    this.searchService.set('searchContext', null);
    this.controllerFor('user-card').set('visible', false);

    const topicController = this.controllerFor('topic');
    const postStream = topicController.get('model.postStream');

    postStream.cancelFilter();

    topicController.set('multiSelect', false);
    topicController.unsubscribe();
    this.controllerFor('composer').set('topic', null);
    this.screenTrack.stop();

    this.appEvents.trigger('header:hide-topic');
  },

  setupController(controller, model) {
    // In case we navigate from one topic directly to another
    isTransitioning = false;

    controller.setProperties({
      model,
      editingTopic: false,
      firstPostExpanded: false
    });

    TopicRoute.trigger('setupTopicController', this);

    this.searchService.set('searchContext', model.get('searchContext'));

    // close the multi select when switching topics
    controller.set('multiSelect', false);
    controller.get('quoteState').clear();

    this.controllerFor('composer').set('topic', model);
    this.topicTrackingState.trackIncoming('all');
    controller.subscribe();

    // We reset screen tracking every time a topic is entered
    this.screenTrack.start(model.get('id'), controller);
  }

});

RSVP.EventTarget.mixin(TopicRoute);
export default TopicRoute;
