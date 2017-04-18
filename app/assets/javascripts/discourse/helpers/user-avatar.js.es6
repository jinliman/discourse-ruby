import { registerUnbound } from 'discourse-common/lib/helpers';
import { avatarImg } from 'discourse/lib/utilities';

function renderAvatar(user, options) {
  options = options || {};

  if (user) {

    const username = Em.get(user, options.usernamePath || 'username');
    const avatarTemplate = Em.get(user, options.avatarTemplatePath || 'avatar_template');

    if (!username || !avatarTemplate) { return ''; }

    let title = options.title;
    if (!title && !options.ignoreTitle) {
      // first try to get a title
      title = Em.get(user, 'title');
      // if there was no title provided
      if (!title) {
        // try to retrieve a description
        const description = Em.get(user, 'description');
        // if a description has been provided
        if (description && description.length > 0) {
          // preprend the username before the description
          title = username + " - " + description;
        }
      }
    }

    return avatarImg({
      size: options.imageSize,
      extraClasses: Em.get(user, 'extras') || options.extraClasses,
      title: title || username,
      avatarTemplate: avatarTemplate
    });
  } else {
    return '';
  }
}

registerUnbound('avatar', function(user, params) {
  return new Handlebars.SafeString(renderAvatar.call(this, user, params));
});

export { renderAvatar };
