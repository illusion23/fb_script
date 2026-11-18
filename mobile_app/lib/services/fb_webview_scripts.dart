import 'dart:convert';

/// JavaScript snippets injected into WebView for on-device Facebook automation,
/// mirroring the multilingual selectors and safety checks in fb_poster.py while
/// supporting both desktop and mobile WebView layouts.
class FbWebViewScripts {
  static const String desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static String detectAuthOrCheckpoint() => '''
    (function() {
      function isVisible(el) {
        if (!el) return false;
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        return rect.width > 0 && rect.height > 0 &&
               style.visibility !== 'hidden' && style.display !== 'none';
      }

      const url = (window.location.href || '').toLowerCase();
      if (url.includes('/login') || url.includes('login.php')) {
        return JSON.stringify({ status: 'login', reason: 'Facebook login required', url: window.location.href });
      }
      if (url.includes('/checkpoint') || url.includes('two_step_verification')) {
        return JSON.stringify({ status: 'checkpoint', reason: 'Facebook security checkpoint or 2FA verification required', url: window.location.href });
      }

      const emailInput = document.querySelector("input[name='email']");
      const passInput = document.querySelector("input[name='pass']");
      if ((emailInput && isVisible(emailInput)) || (passInput && isVisible(passInput))) {
        return JSON.stringify({ status: 'login', reason: 'Facebook login prompt visible on page', url: window.location.href });
      }

      const loginForm = document.querySelector("form[action*='login']");
      if (loginForm && isVisible(loginForm)) {
        return JSON.stringify({ status: 'login', reason: 'Facebook login form visible on page', url: window.location.href });
      }

      // On public group pages when logged out, Facebook may show a top-bar
      // "Log in" button without redirecting to /login.
      const loggedInNav = document.querySelector(
        "[aria-label='Your profile'], [aria-label='Votre profil'], [aria-label='ملفك الشخصي'], " +
        "[aria-label='Account'], [aria-label='Compte'], [aria-label='الحساب'], " +
        "[aria-label='Notifications'], [aria-label='الإشعارات'], " +
        "[aria-label='Messenger']"
      );
      if (!loggedInNav) {
        const loginLinks = document.querySelectorAll("a[href*='/login'], [role='button'], button");
        const loginLabels = ['log in', 'se connecter', 'تسجيل الدخول', 'connexion'];
        for (const el of loginLinks) {
          if (!isVisible(el)) continue;
          const txt = (el.innerText || el.getAttribute('aria-label') || '').trim().toLowerCase();
          if (loginLabels.includes(txt)) {
            return JSON.stringify({
              status: 'login',
              reason: 'Facebook session is not logged in (Log in button visible)',
              url: window.location.href
            });
          }
        }
      }

      return JSON.stringify({ status: 'ok', url: window.location.href });
    })();
  ''';

  static String dismissBannersAndPrompts() => '''
    (function() {
      function isVisible(el) {
        if (!el) return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && window.getComputedStyle(el).visibility !== 'hidden';
      }
      const dismissLabels = [
        'allow all cookies',
        'allow essential and optional cookies',
        'accept all',
        'autoriser tous les cookies',
        'tout accepter',
        'السماح بكل ملفات تعريف الارتباط',
        'قبول الكل',
        'not now',
        'plus tard',
        'ليس الآن'
      ];
      const buttons = document.querySelectorAll("[role='button'], button");
      for (const btn of buttons) {
        if (!isVisible(btn)) continue;
        const txt = (btn.innerText || btn.getAttribute('aria-label') || '').trim().toLowerCase();
        if (dismissLabels.some(l => txt === l || txt.includes(l))) {
          btn.click();
          return JSON.stringify({ clicked: txt });
        }
      }
      return JSON.stringify({ clicked: null });
    })();
  ''';

  static String fillAndSubmitLogin(String email, String password) {
    final e = jsonEncode(email);
    final p = jsonEncode(password);
    return '''
      (function() {
        const emailInput = document.querySelector("input[name='email']");
        const passInput = document.querySelector("input[name='pass']");
        if (!emailInput || !passInput) {
          return JSON.stringify({ ok: false, error: 'Login inputs not visible' });
        }
        function setNativeValue(el, value) {
          const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
          setter.call(el, value);
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        }
        setNativeValue(emailInput, $e);
        setNativeValue(passInput, $p);
        const btn = document.querySelector("button[name='login'], [data-testid='royal-login-button'], input[type='submit'], button[type='submit']");
        if (btn) {
          btn.click();
          return JSON.stringify({ ok: true });
        }
        const form = emailInput.closest('form');
        if (form) {
          form.submit();
          return JSON.stringify({ ok: true });
        }
        return JSON.stringify({ ok: false, error: 'Login submit button not found' });
      })();
    ''';
  }

  static String openGroupComposer(
    bool anonymous, {
    bool preferAnonymous = false,
    bool requireAnonymousIfAvailable = false,
  }) =>
      '''
    (function() {
      const COMPOSER_TRIGGER_LABELS = [
        "Write something...",
        "Write something",
        "Create a public post...",
        "Create a public post",
        "Start a discussion...",
        "Exprimez-vous...",
        "Exprimez-vous",
        "Créer une publication publique...",
        "Écrire quelque chose...",
        "اكتب شيئًا...",
        "اكتب شيئاً...",
        "اكتب شيئا...",
        "اكتب شيئًا",
        "اكتب شيئاً",
        "اكتب شيئا",
        "بم تفكر؟",
        "إنشاء منشور عام..."
      ];
      const ANONYMOUS_TRIGGER_LABELS = [
        "Anonymous post",
        "Post anonymously",
        "Publication anonyme",
        "منشور مجهول الهوية",
        "إنشاء منشور مجهول",
        "مشاركة مجهولة",
        "نشر كمجهول",
        "منشور مجهول"
      ];
      const ANONYMOUS_SWITCH_LABELS = [
        "Post anonymously",
        "Publier anonymement",
        "النشر كمجهول الهوية",
        "النشر كمجهول",
        "نشر مجهول الهوية",
        "نشر مجهول",
        "anonymous post",
        "مشاركة مجهولة"
      ];
      const ANONYMOUS_CONFIRM_LABELS = [
        "Create Anonymous Post",
        "Create anonymous post",
        "Continue",
        "Got it",
        "Publier anonymement",
        "Continuer",
        "Compris",
        "إنشاء منشور مجهول الهوية",
        "متابعة",
        "موافق"
      ];
      const ANONYMOUS_AUTHOR_LABELS = [
        "Anonymous member",
        "Anonymous participant",
        "Anonymous contributor",
        "Posting anonymously",
        "Submit anonymous post",
        "Membre anonyme",
        "Participant anonyme",
        "عضو مجهول الهوية",
        "مشارك مجهول الهوية",
        "عضو مجهول",
        "مشارك مجهول",
        "النشر كمجهول"
      ];
      const JOIN_GROUP_LABELS = [
        "join group",
        "rejoindre le groupe",
        "الانضمام إلى المجموعة",
        "انضمام إلى المجموعة"
      ];

      function isVisible(el) {
        if (!el) return false;
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        return rect.width > 0 && rect.height > 0 &&
               style.visibility !== 'hidden' && style.display !== 'none';
      }

      function findButtonByLabels(root, labels) {
        const els = root.querySelectorAll("[role='button'], button, a[role='button'], div[tabindex='0'], textarea[placeholder]");
        for (const el of els) {
          if (!isVisible(el)) continue;
          const text = (
            (el.innerText || '') + ' ' +
            (el.getAttribute('aria-label') || '') + ' ' +
            (el.getAttribute('placeholder') || '')
          ).toLowerCase();
          for (const label of labels) {
            if (text.includes(label.toLowerCase())) {
              return el;
            }
          }
        }
        return null;
      }

      function getComposerContainer() {
        // 1. Desktop Comet modal dialog with editable textbox
        const dialogs = document.querySelectorAll("[role='dialog']");
        for (const dlg of dialogs) {
          if (!isVisible(dlg)) continue;
          const tb = dlg.querySelector("[role='textbox'][contenteditable='true'], textarea");
          if (tb && isVisible(tb)) return dlg;
        }
        // 2. Fallback for mobile/full-screen composer without [role='dialog']
        const textboxes = document.querySelectorAll("[role='textbox'][contenteditable='true'], form[action*='composer'] textarea, [data-sigil*='composer'] textarea");
        for (const tb of textboxes) {
          if (!isVisible(tb)) continue;
          const container = tb.closest("[role='dialog'], form, [data-sigil*='composer'], [role='main']") || tb.parentElement;
          if (container) return container;
        }
        return null;
      }

      // Dismiss cookie or anonymous info modals if open without textbox
      for (const dlg of document.querySelectorAll("[role='dialog']")) {
        if (!isVisible(dlg)) continue;
        if (dlg.querySelector("[role='textbox'][contenteditable='true'], textarea")) continue;
        const confirmBtn = findButtonByLabels(dlg, ANONYMOUS_CONFIRM_LABELS);
        if (confirmBtn) {
          confirmBtn.click();
          return JSON.stringify({ status: 'dismissed_intro' });
        }
      }

      let container = getComposerContainer();
      if (!container) {
        const root = document.querySelector("[role='main']") ||
                     document.querySelector("#root") ||
                     document.querySelector("#MRoot") ||
                     document.body;

        if (!root) {
          return JSON.stringify({
            status: 'waiting_trigger',
            reason: 'No DOM root yet',
            url: window.location.href,
            vw: window.innerWidth,
            vh: window.innerHeight
          });
        }

        let trigger = null;
        if ($anonymous || $preferAnonymous) {
          trigger = findButtonByLabels(root, ANONYMOUS_TRIGGER_LABELS);
        }
        if (!trigger) {
          trigger = findButtonByLabels(root, COMPOSER_TRIGGER_LABELS);
        }
        if (!trigger) {
          const joinBtn = findButtonByLabels(root, JOIN_GROUP_LABELS);
          if (joinBtn) {
            return JSON.stringify({
              status: 'not_a_member',
              reason: 'Join group button is visible; account is not a member of this group.',
              url: window.location.href
            });
          }
          return JSON.stringify({
            status: 'waiting_trigger',
            url: window.location.href,
            vw: window.innerWidth,
            vh: window.innerHeight,
            hasMain: !!document.querySelector("[role='main']"),
            readyState: document.readyState
          });
        }
        trigger.scrollIntoView({ block: 'center' });
        trigger.click();
        return JSON.stringify({ status: 'trigger_clicked' });
      }

      function isAnonymousSwitch(sw) {
        const directLabel = ((sw.getAttribute('aria-label') || '') + ' ' + (sw.innerText || '')).toLowerCase();
        if (ANONYMOUS_SWITCH_LABELS.some(l => directLabel.includes(l.toLowerCase()))) {
          return true;
        }
        let parent = sw.parentElement;
        for (let depth = 0; depth < 6 && parent; depth++) {
          if (parent.querySelector("[role='textbox'][contenteditable='true'], textarea")) {
            break;
          }
          const pText = (parent.innerText || '').toLowerCase();
          if (pText.length <= 450 && ANONYMOUS_SWITCH_LABELS.some(l => pText.includes(l.toLowerCase()))) {
            return true;
          }
          parent = parent.parentElement;
        }
        return false;
      }

      function hasAnonymousOption(cont) {
        const dlgText = (cont.innerText || '').toLowerCase();
        if (ANONYMOUS_AUTHOR_LABELS.some(l => dlgText.includes(l.toLowerCase()))) return true;
        if (ANONYMOUS_SWITCH_LABELS.some(l => dlgText.includes(l.toLowerCase()))) return true;
        if (findButtonByLabels(cont, ANONYMOUS_SWITCH_LABELS)) return true;
        const switches = cont.querySelectorAll("[role='switch'], [role='checkbox'], input[type='checkbox']");
        for (const sw of switches) {
          if (isVisible(sw) && isAnonymousSwitch(sw)) return true;
        }
        return false;
      }

      if ($anonymous || $preferAnonymous) {
        const dlgText = (container.innerText || '').toLowerCase();
        const isAnonAuthor = ANONYMOUS_AUTHOR_LABELS.some(l => dlgText.includes(l.toLowerCase()));
        let isAnonChecked = false;
        const switches = container.querySelectorAll("[role='switch'], [role='checkbox'], input[type='checkbox']");
        for (const sw of switches) {
          if (!isVisible(sw) || !isAnonymousSwitch(sw)) continue;
          if (sw.getAttribute('aria-checked') === 'true' || sw.checked) {
            isAnonChecked = true;
          } else {
            sw.click();
            return JSON.stringify({ status: 'toggled_anonymous' });
          }
        }
        if (!isAnonAuthor && !isAnonChecked) {
          const btnSwitch = findButtonByLabels(container, ANONYMOUS_SWITCH_LABELS);
          if (btnSwitch) {
            btnSwitch.click();
            return JSON.stringify({ status: 'toggled_anonymous' });
          }
          if ($anonymous) {
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
            return JSON.stringify({ status: 'anonymous_unavailable' });
          }
          return JSON.stringify({ status: 'composer_ready', usedAnonymous: false });
        }
        return JSON.stringify({ status: 'composer_ready', usedAnonymous: true });
      } else if ($requireAnonymousIfAvailable && hasAnonymousOption(container)) {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        return JSON.stringify({
          status: 'anonymous_required_blocked',
          reason: 'Group has anonymous posting active; skipped without anonymous option.'
        });
      }

      return JSON.stringify({ status: 'composer_ready', usedAnonymous: false });
    })();
  ''';

  static String fillAndSubmitPost({
    required String message,
    required List<Map<String, String>> imagesBase64,
    required bool dryRun,
    bool requireAnonymous = false,
  }) {
    final msgJson = jsonEncode(message);
    final imgsJson = jsonEncode(imagesBase64);
    return '''
      (function() {
        const SUBMIT_BUTTON_NAMES = ["post", "publier", "نشر", "submit", "envoyer", "إرسال", "publicar", "posten"];
        const PHOTO_BUTTON_LABELS = ["photo/video", "photo / vidéo", "photo/vidéo", "صورة/فيديو"];

        function isVisible(el) {
          if (!el) return false;
          const rect = el.getBoundingClientRect();
          const style = window.getComputedStyle(el);
          return rect.width > 0 && rect.height > 0 &&
                 style.visibility !== 'hidden' && style.display !== 'none';
        }

        let container = null;
        for (const dlg of document.querySelectorAll("[role='dialog']")) {
          if (!isVisible(dlg)) continue;
          const tb = dlg.querySelector("[role='textbox'][contenteditable='true'], textarea");
          if (tb && isVisible(tb)) {
            container = dlg;
            break;
          }
        }
        if (!container) {
          const textboxes = document.querySelectorAll("[role='textbox'][contenteditable='true'], form[action*='composer'] textarea, [data-sigil*='composer'] textarea");
          for (const tb of textboxes) {
            if (!isVisible(tb)) continue;
            container = tb.closest("[role='dialog'], form, [data-sigil*='composer'], [role='main']") || tb.parentElement;
            if (container) break;
          }
        }

        if (!container) {
          return JSON.stringify({ status: 'error', error: 'Composer dialog not open' });
        }

        const msg = $msgJson;
        if (msg && msg.trim().length > 0) {
          const tb = container.querySelector("[role='textbox'][contenteditable='true'], textarea");
          if (!tb) {
            return JSON.stringify({ status: 'error', error: 'Composer textbox not found' });
          }
          tb.focus();
          tb.click();
          if (tb.tagName === 'TEXTAREA') {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
            setter.call(tb, msg);
            tb.dispatchEvent(new Event('input', { bubbles: true }));
            tb.dispatchEvent(new Event('change', { bubbles: true }));
          } else {
            try {
              document.execCommand('selectAll', false, null);
              document.execCommand('insertText', false, msg);
            } catch (e) {
              tb.innerText = msg;
              tb.dispatchEvent(new InputEvent('input', { bubbles: true, data: msg, inputType: 'insertText' }));
            }
          }
        }

        const imgs = $imgsJson;
        if (imgs && imgs.length > 0) {
          let fileInput = container.querySelector("input[type='file'][accept*='image' i]") ||
                          container.querySelector("input[type='file']");
          if (!fileInput) {
            const buttons = container.querySelectorAll("[role='button'], button");
            for (const b of buttons) {
              const txt = ((b.innerText || '') + ' ' + (b.getAttribute('aria-label') || '')).toLowerCase();
              if (PHOTO_BUTTON_LABELS.some(l => txt.includes(l))) {
                b.click();
                break;
              }
            }
            fileInput = container.querySelector("input[type='file']");
          }
          if (fileInput) {
            try {
              const dt = new DataTransfer();
              for (const item of imgs) {
                const byteChars = atob(item.data);
                const byteNums = new Array(byteChars.length);
                for (let i = 0; i < byteChars.length; i++) {
                  byteNums[i] = byteChars.charCodeAt(i);
                }
                const blob = new Blob([new Uint8Array(byteNums)], { type: item.mimeType || 'image/jpeg' });
                dt.items.add(new File([blob], item.name || 'image.jpg', { type: item.mimeType || 'image/jpeg' }));
              }
              fileInput.files = dt.files;
              fileInput.dispatchEvent(new Event('change', { bubbles: true }));
            } catch (err) {
              return JSON.stringify({ status: 'error', error: 'Failed to attach image in WebView: ' + err });
            }
          }
        }

        if ($dryRun) {
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
          return JSON.stringify({ status: 'dry_run_ok' });
        }

        if ($requireAnonymous) {
          const ANONYMOUS_AUTHOR_LABELS = [
            "Anonymous member", "Anonymous participant", "Anonymous contributor",
            "Posting anonymously", "Submit anonymous post", "Membre anonyme",
            "Participant anonyme", "عضو مجهول الهوية", "مشارك مجهول الهوية",
            "عضو مجهول", "مشارك مجهول", "النشر كمجهول"
          ];
          const ANONYMOUS_SWITCH_LABELS = [
            "Post anonymously", "Publier anonymement", "النشر كمجهول الهوية",
            "النشر كمجهول", "نشر مجهول الهوية", "نشر مجهول",
            "anonymous post", "مشاركة مجهولة"
          ];
          const dlgText = (container.innerText || '').toLowerCase();
          const isAnonAuthor = ANONYMOUS_AUTHOR_LABELS.some(l => dlgText.includes(l.toLowerCase()));
          let isAnonChecked = false;
          for (const sw of container.querySelectorAll("[role='switch'], [role='checkbox'], input[type='checkbox']")) {
            if (!isVisible(sw)) continue;
            const directLabel = ((sw.getAttribute('aria-label') || '') + ' ' + (sw.innerText || '')).toLowerCase();
            let matched = ANONYMOUS_SWITCH_LABELS.some(l => directLabel.includes(l.toLowerCase()));
            if (!matched) {
              let parent = sw.parentElement;
              for (let depth = 0; depth < 6 && parent; depth++) {
                if (parent.querySelector("[role='textbox'][contenteditable='true'], textarea")) break;
                const pText = (parent.innerText || '').toLowerCase();
                if (pText.length <= 450 && ANONYMOUS_SWITCH_LABELS.some(l => pText.includes(l.toLowerCase()))) {
                  matched = true;
                  break;
                }
                parent = parent.parentElement;
              }
            }
            if (matched && (sw.getAttribute('aria-checked') === 'true' || sw.checked)) {
              isAnonChecked = true;
            }
          }
          if (!isAnonAuthor && !isAnonChecked) {
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
            return JSON.stringify({ status: 'anonymous_unavailable' });
          }
        }

        const buttons = container.querySelectorAll("[role='button'], button, input[type='submit']");
        let submitBtn = null;
        for (const btn of buttons) {
          if (!isVisible(btn)) continue;
          const label = (btn.innerText || btn.getAttribute('aria-label') || btn.value || '').trim().toLowerCase();
          if (SUBMIT_BUTTON_NAMES.includes(label)) {
            submitBtn = btn;
            break;
          }
        }
        if (!submitBtn) {
          return JSON.stringify({ status: 'error', error: 'Submit button (Post/Publier/نشر) not found' });
        }
        if (submitBtn.getAttribute('aria-disabled') === 'true' || submitBtn.disabled) {
          return JSON.stringify({ status: 'waiting_submit' });
        }
        submitBtn.click();
        return JSON.stringify({ status: 'submitted' });
      })();
    ''';
  }

  static String isComposerClosed() => '''
    (function() {
      const dialogs = document.querySelectorAll("[role='dialog']");
      for (const dlg of dialogs) {
        const rect = dlg.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0 &&
            dlg.querySelector("[role='textbox'][contenteditable='true'], textarea")) {
          return 'false';
        }
      }
      return 'true';
    })();
  ''';
}
