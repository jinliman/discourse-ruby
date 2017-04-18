import renderTag from 'discourse/lib/render-tag';

let callbacks = null;
let priorities = null;

export function addTagsHtmlCallback(callback, options) {
  callbacks = callbacks || [];
  priorities = priorities || [];
  const priority = (options && options.priority) || 0;

  let i = 0;
  while(i < priorities.length && priorities[i] > priority) {
    i += 1;
  }

  priorities.splice(i, 0, priority);
  callbacks.splice(i, 0, callback);
};

export default function(topic, params){
  let tags = topic.tags;
  let buffer = "";

  if (params && params.mode === "list") {
    tags = topic.get("visibleListTags");
  }

  let customHtml = null;
  if (callbacks) {
    callbacks.forEach((c) => {
      const html = c(topic, params);
      if (html) {
        if (customHtml) {
          customHtml += html;
        } else {
          customHtml = html;
        }
      }
    });
  }

  if (customHtml || (tags && tags.length > 0)) {
    buffer = "<div class='discourse-tags'>";
    if (tags) {
      for(let i=0; i<tags.length; i++){
        buffer += renderTag(tags[i]);
      }
    }

    if (customHtml) {
      buffer += customHtml;
    }

    buffer += "</div>";
  }
  return buffer;
};
