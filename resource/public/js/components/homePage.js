'use strict';

import auth from '../auth.js';
import routing from '../routing.js';

class HomePage extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    // TODO refresh token if possible.
    if (auth.isAuthenticated()) {
      routing.push('/user/contacts', {});
    }

    this.innerHTML = '<github-login></github-login>';
  }
}

window.customElements.define('home-page', HomePage);

export default {};
