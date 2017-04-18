import { default as computed, observes }  from 'ember-addons/ember-computed-decorators';
import Composer from 'discourse/models/composer';
import afterTransition from 'discourse/lib/after-transition';
import positioningWorkaround from 'discourse/lib/safari-hacks';
import { headerHeight } from 'discourse/components/site-header';

export default Ember.Component.extend({
  elementId: 'reply-control',

  classNameBindings: ['composer.creatingPrivateMessage:private-message',
                      'composeState',
                      'composer.loading',
                      'composer.canEditTitle:edit-title',
                      'composer.createdPost:created-post',
                      'composer.creatingTopic:topic',
                      'composer.whisper:composing-whisper'],

  @computed('composer.composeState')
  composeState(composeState) {
    return composeState || Composer.CLOSED;
  },

  movePanels(sizePx) {
    $('#main-outlet').css('padding-bottom', sizePx);

    // signal the progress bar it should move!
    this.appEvents.trigger("composer:resized");
  },

  @observes('composeState', 'composer.action', 'composer.canEditTopicFeaturedLink')
  resize() {
    Ember.run.scheduleOnce('afterRender', () => {
      if (!this.element || this.isDestroying || this.isDestroyed) { return; }

      const h = $('#reply-control').height() || 0;
      this.movePanels(h + "px");

      // Figure out the size of the fields
      const $fields = this.$('.composer-fields');
      const fieldPos = $fields.position();
      if (fieldPos) {
        this.$('.wmd-controls').css('top', $fields.height() + fieldPos.top + 5);
      }

      // get the submit panel height
      const submitPos = this.$('.submit-panel').position();
      if (submitPos) {
        this.$('.wmd-controls').css('bottom', h - submitPos.top + 7);
      }
    });
  },

  keyUp() {
    this.sendAction('typed');

    const lastKeyUp = new Date();
    this._lastKeyUp = lastKeyUp;

    // One second from now, check to see if the last key was hit when
    // we recorded it. If it was, the user paused typing.
    Ember.run.cancel(this._lastKeyTimeout);
    this._lastKeyTimeout = Ember.run.later(() => {
      if (lastKeyUp !== this._lastKeyUp) { return; }
      this.appEvents.trigger('composer:find-similar');
    }, 1000);
  },

  keyDown(e) {
    if (e.which === 27) {
      this.sendAction('cancelled');
      return false;
    } else if (e.which === 13 && (e.ctrlKey || e.metaKey)) {
      // CTRL+ENTER or CMD+ENTER
      this.sendAction('save');
      return false;
    }
  },

  @observes('composeState')
  disableFullscreen() {
    if (this.get('composeState') !== Composer.OPEN && positioningWorkaround.blur) {
      positioningWorkaround.blur();
    }
  },

  didInsertElement() {
    this._super();
    const $replyControl = $('#reply-control');
    const resize = () => Ember.run(() => this.resize());

    $replyControl.DivResizer({
      resize,
      maxHeight: winHeight => winHeight - headerHeight(),
      onDrag: sizePx => this.movePanels(sizePx)
    });

    const triggerOpen = () => {
      if (this.get('composer.composeState') === Composer.OPEN) {
        this.appEvents.trigger('composer:opened');
      }
    };
    triggerOpen();

    afterTransition($replyControl, () => {
      resize();
      triggerOpen();
    });
    positioningWorkaround(this.$());

    this.appEvents.on('composer:resize', this, this.resize);
  },

  willDestroyElement() {
    this._super();
    this.appEvents.off('composer:resize', this, this.resize);
  },

  click() {
    this.sendAction('openIfDraft');
  },

});
