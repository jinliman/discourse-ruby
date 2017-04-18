import { on } from "ember-addons/ember-computed-decorators";

export default Ember.Component.extend({
  elementId: 'discourse-modal',
  classNameBindings: [':modal', ':hidden', 'modalClass'],
  attributeBindings: ['data-keyboard'],

  // We handle ESC ourselves
  'data-keyboard': 'false',

  @on("didInsertElement")
  setUp() {
    $('html').on('keydown.discourse-modal', e => {
      if (e.which === 27) {
        Em.run.next(() => $('.modal-header a.close').click());
      }
    });

    this.appEvents.on('modal:body-shown', data => {
      if (data.title) {
        this.set('title', I18n.t(data.title));
      } else if (data.rawTitle) {
        this.set('title', data.rawTitle);
      }
    });
  },

  @on("willDestroyElement")
  cleanUp() {
    $('html').off('keydown.discourse-modal');
  },

  click(e) {
    const $target = $(e.target);
    if ($target.hasClass("modal-middle-container") ||
        $target.hasClass("modal-outer-container")) {
      // Delegate click to modal close if clicked outside.
      // We do this because some CSS of ours seems to cover
      // the backdrop and makes it unclickable.
      $('.modal-header a.close').click();
    }
  }
});
