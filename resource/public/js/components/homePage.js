'use strict';

import auth from '../auth.js';
import routing from '../routing.js';

class HomePage extends HTMLElement {
  constructor() {
    super();
    const template = document.getElementById(
      'template-home-page',
    ).content;
    this.root = this.attachShadow({ mode: 'open' });
    this.root.appendChild(template.cloneNode(true));
  }

  connectedCallback() {
    // TODO refresh token if possible.
    if (auth.isAuthenticated()) {
      routing.push('/user/contacts', {});
    }
  }
}

window.customElements.define('home-page', HomePage);

export default {};
