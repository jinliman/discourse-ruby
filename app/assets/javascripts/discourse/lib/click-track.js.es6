import { ajax } from 'discourse/lib/ajax';
import DiscourseURL from 'discourse/lib/url';
import { wantsNewWindow } from 'discourse/lib/intercept-click';
import { selectedText } from 'discourse/lib/utilities';

export function isValidLink($link) {
  return ($link.hasClass("track-link") ||
          $link.closest('.hashtag,.badge-category,.onebox-result,.onebox-body').length === 0);
};

export default {
  trackClick(e) {
    // cancel click if triggered as part of selection.
    if (selectedText() !== "") { return false; }

    var $link = $(e.currentTarget);

    // don't track lightboxes, group mentions or links with disabled tracking
    if ($link.hasClass('lightbox') || $link.hasClass('mention-group') ||
        $link.hasClass('no-track-link') || $link.hasClass('hashtag')) {
      return true;
    }

    // don't track links in quotes or in elided part
    if ($link.parents('aside.quote,.elided').length) { return true; }

    var href = $link.attr('href') || $link.data('href'),
        $article = $link.closest('article,.excerpt,#revisions'),
        postId = $article.data('post-id'),
        topicId = $('#topic').data('topic-id') || $article.data('topic-id'),
        userId = $link.data('user-id');

    if (!href || href.trim().length === 0) { return false; }
    if (href.indexOf("mailto:") === 0) { return true; }

    if (!userId) userId = $article.data('user-id');

    var ownLink = userId && (userId === Discourse.User.currentProp('id')),
        trackingUrl = Discourse.getURL("/clicks/track?url=" + encodeURIComponent(href));
    if (postId && (!$link.data('ignore-post-id'))) {
      trackingUrl += "&post_id=" + encodeURI(postId);
    }
    if (topicId) {
      trackingUrl += "&topic_id=" + encodeURI(topicId);
    }

    // Update badge clicks unless it's our own
    if (!ownLink) {
      const $badge = $('span.badge', $link);
      if ($badge.length === 1) {
        // don't update counts in category badge nor in oneboxes (except when we force it)
        if (isValidLink($link)) {
          const html = $badge.html();
          const key = `${new Date().toLocaleDateString()}-${postId}-${href}`;
          if (/^\d+$/.test(html) && !sessionStorage.getItem(key)) {
            sessionStorage.setItem(key, true);
            $badge.html(parseInt(html, 10) + 1);
          }
        }
      }
    }

    // If they right clicked, change the destination href
    if (e.which === 3) {
      var destination = Discourse.SiteSettings.track_external_right_clicks ? trackingUrl : href;
      $link.attr('href', destination);
      return true;
    }

    // if they want to open in a new tab, do an AJAX request
    if (wantsNewWindow(e)) {
      ajax("/clicks/track", {
        data: {
          url: href,
          post_id: postId,
          topic_id: topicId,
          redirect: false
        },
        dataType: 'html'
      });
      return true;
    }

    e.preventDefault();

    // We don't track clicks on quote back buttons
    if ($link.hasClass('back') || $link.hasClass('quote-other-topic')) { return true; }

    // Remove the href, put it as a data attribute
    if (!$link.data('href')) {
      $link.addClass('no-href');
      $link.data('href', $link.attr('href'));
      $link.attr('href', null);
      // Don't route to this URL
      $link.data('auto-route', true);
    }

    // restore href
    setTimeout(() => {
      $link.removeClass('no-href');
      $link.attr('href', $link.data('href'));
      $link.data('href', null);
    }, 50);

    // warn the user if they can't download the file
    if (Discourse.SiteSettings.prevent_anons_from_downloading_files && $link.hasClass("attachment") && !Discourse.User.current()) {
      bootbox.alert(I18n.t("post.errors.attachment_download_requires_login"));
      return false;
    }

    // If we're on the same site, use the router and track via AJAX
    if (DiscourseURL.isInternal(href) && !$link.hasClass('attachment')) {
      ajax("/clicks/track", {
        data: {
          url: href,
          post_id: postId,
          topic_id: topicId,
          redirect: false
        },
        dataType: 'html'
      });
      DiscourseURL.routeTo(href);
      return false;
    }

    // Otherwise, use a custom URL with a redirect
    if (Discourse.User.currentProp('external_links_in_new_tab')) {
      var win = window.open(trackingUrl, '_blank');
      win.focus();
    } else {
      DiscourseURL.redirectTo(trackingUrl);
    }

    return false;
  }
};
