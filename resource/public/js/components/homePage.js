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

    this.innerHTML = `
      <div>
        <h3>Login or sign up</h3>
        <github-login></github-login>
      </div>
    `;
  }
}

window.customElements.define('home-page', HomePage);

export default {};
