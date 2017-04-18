import computed from "ember-addons/ember-computed-decorators";
import { bufferedRender } from 'discourse-common/lib/buffered-render';

export default Ember.Component.extend(bufferedRender({
  tagName: 'li',
  classNameBindings: ['active', 'content.hasIcon:has-icon'],
  attributeBindings: ['title'],
  hidden: Em.computed.not('content.visible'),
  rerenderTriggers: ['content.count'],

  @computed("content.categoryName", "content.name")
  title(categoryName, name) {
    const extra = {};

    if (categoryName) {
      name = "category";
      extra.categoryName = categoryName;
    }

    return I18n.t("filters." + name.replace("/", ".") + ".help", extra);
  },

  @computed("content.filterMode", "filterMode")
  active(contentFilterMode, filterMode) {
    return contentFilterMode === filterMode ||
           filterMode.indexOf(contentFilterMode) === 0;
  },

  buildBuffer(buffer) {
    const content = this.get('content');
    buffer.push("<a href='" + content.get('href') + "'>");
    if (content.get('hasIcon')) {
      buffer.push("<span class='" + content.get('name') + "'></span>");
    }
    buffer.push(this.get('content.displayName'));
    buffer.push("</a>");
  }
}));
