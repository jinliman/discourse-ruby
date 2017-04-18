import { WidgetClickHook,
         WidgetClickOutsideHook,
         WidgetKeyUpHook,
         WidgetKeyDownHook,
         WidgetDragHook } from 'discourse/widgets/hooks';
import { h } from 'virtual-dom';
import DecoratorHelper from 'discourse/widgets/decorator-helper';

function emptyContent() { }

const _registry = {};
let _dirty = {};

export function keyDirty(key, options) {
  _dirty[key] = options || {};
}

export function renderedKey(key) {
  delete _dirty[key];
}

export function queryRegistry(name) {
  return _registry[name];
}

const _decorators = {};

export function decorateWidget(widgetName, cb) {
  _decorators[widgetName] = _decorators[widgetName] || [];
  _decorators[widgetName].push(cb);
}

export function applyDecorators(widget, type, attrs, state) {
  const decorators = _decorators[`${widget.name}:${type}`] || [];

  if (decorators.length) {
    const helper = new DecoratorHelper(widget, attrs, state);
    return decorators.map(d => d(helper));
  }

  return [];
}

const _customSettings = {};
export function changeSetting(widgetName, settingName, newValue) {
  _customSettings[widgetName] = _customSettings[widgetName] || {};
  _customSettings[widgetName][settingName] = newValue;
}

function drawWidget(builder, attrs, state) {
  const properties = {};

  if (this.buildClasses) {
    let classes = this.buildClasses(attrs, state) || [];
    if (!Array.isArray(classes)) { classes = [classes]; }

    const customClasses = applyDecorators(this, 'classNames', attrs, state);
    if (customClasses && customClasses.length) {
      classes = classes.concat(customClasses);
    }

    if (classes.length) {
      properties.className = classes.join(' ');
    }
  }
  if (this.buildId) {
    properties.id = this.buildId(attrs);
  }

  if (this.buildAttributes) {
    properties.attributes = this.buildAttributes(attrs);
  }

  if (this.keyUp) {
    properties['widget-key-up'] = new WidgetKeyUpHook(this);
  }

  if (this.keyDown) {
    properties['widget-key-down'] = new WidgetKeyDownHook(this);
  }

  if (this.clickOutside) {
    properties['widget-click-outside'] = new WidgetClickOutsideHook(this);
  }
  if (this.click) {
    properties['widget-click'] = new WidgetClickHook(this);
  }
  if (this.drag) {
    properties['widget-drag'] = new WidgetDragHook(this);
  }

  const attributes = properties['attributes'] || {};
  properties.attributes = attributes;

  if (this.title) {
    if (typeof this.title === 'function') {
      attributes.title = this.title(attrs, state);
    } else {
      attributes.title = I18n.t(this.title);
    }
  }

  let contents = this.html(attrs, state);
  if (this.name) {
    const beforeContents = applyDecorators(this, 'before', attrs, state) || [];
    const afterContents = applyDecorators(this, 'after', attrs, state) || [];
    contents = beforeContents.concat(contents).concat(afterContents);
  }

  return h(this.tagName || 'div', properties, contents);
}

export function createWidget(name, opts) {
  const result = class CustomWidget extends Widget {};

  if (name) {
    _registry[name] = result;
  }

  opts.name = name;
  opts.html = opts.html || emptyContent;
  opts.draw = drawWidget;

  Object.keys(opts).forEach(k => result.prototype[k] = opts[k]);
  return result;
}

export function reopenWidget(name, opts) {
  let existing = _registry[name];
  if (!existing) {
    console.error(`Could not find widget ${name} in registry`);
    return;
  }

  Object.keys(opts).forEach(k => existing.prototype[k] = opts[k]);
  return existing;
}

export default class Widget {
  constructor(attrs, register, opts) {
    opts = opts || {};
    this.attrs = attrs || {};
    this.mergeState = opts.state;
    this.model = opts.model;
    this.register = register;

    register.deprecateContainer(this);

    this.key = this.buildKey ? this.buildKey(attrs) : null;
    this.site = register.lookup('site:main');
    this.siteSettings = register.lookup('site-settings:main');
    this.currentUser = register.lookup('current-user:main');
    this.capabilities = register.lookup('capabilities:main');
    this.store = register.lookup('store:main');
    this.appEvents = register.lookup('app-events:main');
    this.keyValueStore = register.lookup('key-value-store:main');

    // Helps debug widgets
    if (Discourse.Environment === "development" || Ember.testing) {
      const ds = this.defaultState(attrs);
      if (typeof ds !== "object") {
        throw `defaultState must return an object`;
      } else if (Object.keys(ds).length > 0 && !this.key) {
        throw `you need a key when using state in ${this.name}`;
      }
    }

    if (this.name) {
      const custom = _customSettings[this.name];
      if (custom) {
        Object.keys(custom).forEach(k => this.settings[k] = custom[k]);
      }
    }
  }

  defaultState() {
    return {};
  }

  destroy() {
    console.log('destroy called');
  }

  render(prev) {
    if (prev && prev.key && prev.key === this.key) {
      this.state = prev.state;
    } else {
      this.state = this.defaultState(this.attrs, this.state);
    }

    // Sometimes we pass state down from the parent
    if (this.mergeState) {
      this.state = _.merge(this.state, this.mergeState);
    }

    if (prev) {
      const dirtyOpts = _dirty[prev.key] || {};
      if (prev.shadowTree) {
        this.shadowTree = true;
        if (!dirtyOpts && !_dirty['*']) {
          return prev.vnode;
        }
      }
      renderedKey(prev.key);

      const refreshAction = dirtyOpts.onRefresh;
      if (refreshAction) {
        this.sendWidgetAction(refreshAction, dirtyOpts.refreshArg);
      }
    }

    return this.draw(h, this.attrs, this.state);
  }

  _findAncestorWithProperty(property) {
    let widget = this;
    while (widget) {
      const value = widget[property];
      if (value) {
        return widget;
      }
      widget = widget.parentWidget;
    }
  }

  _findView() {
    const widget = this._findAncestorWithProperty('_emberView');
    if (widget) {
      return widget._emberView;
    }
  }

  attach(widgetName, attrs, opts) {
    let WidgetClass = _registry[widgetName];

    if (!WidgetClass) {
      if (!this.register) {
        console.error("couldn't find register");
        return;
      }
      WidgetClass = this.register.lookupFactory(`widget:${widgetName}`);
    }

    if (WidgetClass) {
      const result = new WidgetClass(attrs, this.register, opts);
      result.parentWidget = this;
      return result;
    } else {
      throw `Couldn't find ${widgetName} factory`;
    }
  }

  scheduleRerender() {
    let widget = this;
    while (widget) {
      if (widget.shadowTree) {
        keyDirty(widget.key);
      }

      const rerenderable = widget._rerenderable;
      if (rerenderable) {
        return rerenderable.queueRerender();
      }

      widget = widget.parentWidget;
    }
  }

  _sendComponentAction(name, param) {
    let promise;

    const view = this._findView();
    if (view) {
      const method = view.get(name);
      if (!method) {
        console.warn(`${name} not found`);
        return;
      }

      if (typeof method === "string") {
        view.sendAction(method, param);
        promise = Ember.RSVP.resolve();
      } else {
        const target = view.get('targetObject');
        promise = method.call(target, param);
        if (!promise || !promise.then) {
          promise = Ember.RSVP.resolve(promise);
        }
      }
    }

    return this.rerenderResult(() => promise);
  }

  findAncestorModel() {
    const modelWidget = this._findAncestorWithProperty('model');
    if (modelWidget) {
      return modelWidget.model;
    }
  }

  rerenderResult(fn) {
    this.scheduleRerender();
    const result = fn();
    // re-render after any promises complete, too!
    if (result && result.then) {
      return result.then(() => this.scheduleRerender());
    }
    return result;
  }

  sendWidgetEvent(name, attrs) {
    const methodName = `${name}Event`;
    return this.rerenderResult(() => {
      const widget = this._findAncestorWithProperty(methodName);
      if (widget) {
        return widget[methodName](attrs);
      }
    });
  }

  sendWidgetAction(name, param) {
    return this.rerenderResult(() => {
      const widget = this._findAncestorWithProperty(name);
      if (widget) {
        return widget[name].call(widget, param);
      }

      return this._sendComponentAction(name, param || this.findAncestorModel());
    });
  }
}

Widget.prototype.type = 'Thunk';
