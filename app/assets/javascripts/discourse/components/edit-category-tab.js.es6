import { propertyEqual } from 'discourse/lib/computed';

export default Em.Component.extend({
  tagName: 'li',
  classNameBindings: ['active', 'tabClassName'],

  tabClassName: function() {
    return 'edit-category-' + this.get('tab');
  }.property('tab'),

  active: propertyEqual('selectedTab', 'tab'),

  title: function() {
    return I18n.t('category.' + this.get('tab').replace('-', '_'));
  }.property('tab'),

  didInsertElement() {
    this._super();
    Ember.run.scheduleOnce('afterRender', this, this._addToCollection);
  },

  _addToCollection: function() {
    this.get('panels').addObject(this.get('tabClassName'));
  },

  actions: {
    select: function() {
      this.set('selectedTab', this.get('tab'));
    }
  }
});
