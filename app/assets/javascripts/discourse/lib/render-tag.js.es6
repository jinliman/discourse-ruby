export default function renderTag(tag, params) {
  params = params || {};
  tag = Handlebars.Utils.escapeExpression(tag);
  const classes = ['tag-' + tag, 'discourse-tag'];
  const tagName = params.tagName || "a";
  const href = (tagName === "a" && !params.noHref) ? " href='" + Discourse.getURL("/tags/" + tag) + "' " : "";

  if (Discourse.SiteSettings.tag_style || params.style) {
    classes.push(params.style || Discourse.SiteSettings.tag_style);
  }

  let val = "<" + tagName + href + " class='" + classes.join(" ") + "'>" + tag + "</" + tagName + ">";

  if (params.count) {
    val += " <span class='discourse-tag-count'>x" + params.count + "</span>";
  }

  return val;
};
