'use strict';

import auth from '../auth.js';
import routing from '../routing.js';

class AuthGithubCallback extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    (async () => {
      const searchParams = new URLSearchParams(location.search);
      const code = searchParams.get('code');
      const state = searchParams.get('state');

      await auth.fetchGithubToken(code, state);
      routing.push('/', {});
    })();
  }
}

window.customElements.define('auth-github-callback', AuthGithubCallback);

export default {};
