'use strict';

import routing from '../routing.js';

class InternalLink extends HTMLElement {
  constructor() {
    super();
    const template = document.getElementById(
      'template-internal-link',
    ).content;
    this.root = this.attachShadow({ mode: 'open' });
    this.root.appendChild(template.cloneNode(true));

    this.childLink().addEventListener('click', (event) => {
      event.preventDefault();
      routing.push(this.getAttribute('href'), {});
    });
  }

  connectedCallback() {
    this.childLink().href = this.getAttribute('href');
  }

  childLink() {
    return this.root.querySelector('a');
  }
}

window.customElements.define('internal-link', InternalLink);

export default {};
