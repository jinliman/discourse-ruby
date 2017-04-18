import { iconHTML } from 'discourse-common/helpers/fa-icon';
import { bufferedRender } from 'discourse-common/lib/buffered-render';

export default Ember.Component.extend(bufferedRender({
  tagName: 'th',
  classNames: ['sortable'],
  attributeBindings: ['title'],
  rerenderTriggers: ['order', 'asc'],

  title: function() {
    const labelKey = 'directory.' + this.get('field');
    return I18n.t(labelKey + '_long', { defaultValue: I18n.t(labelKey) });
  }.property('field'),

  buildBuffer(buffer) {
    const icon = this.get('icon');
    if (icon) {
      buffer.push(iconHTML(icon));
    }

    const field = this.get('field');
    buffer.push(I18n.t('directory.' + field));

    if (field === this.get('order')) {
      buffer.push(iconHTML(this.get('asc') ? 'chevron-up' : 'chevron-down'));
    }
  },

  click() {
    const currentOrder = this.get('order'),
          field = this.get('field');

    if (currentOrder === field) {
      this.set('asc', this.get('asc') ? null : true);
    } else {
      this.setProperties({ order: field, asc: null });
    }
  }
}));
