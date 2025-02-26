'use strict';

import time from '../time.js';

class ContactItem extends HTMLElement {
  static observedAttributes = [
    'data-full-name',
    'data-frequency-days',
    'data-due-at',
  ];

  constructor() {
    super();
    const template = document.getElementById(
      "template-contact-item",
    ).content;
    this.root = this.attachShadow({ mode: "open" });
    this.root.appendChild(template.cloneNode(true));
    this.nowSeconds = time.nowSeconds();
  }

  setFullName(fullName) {
    this.root.querySelector('.full-name').textContent = fullName;
  }

  setFrequencyDays(frequencyDays) {
    this.root.querySelector('.frequency-days').textContent = `(${frequencyDays}d 🕔)`;
  }

  setDueAt(dueAt) {
    const dueAtText = `${time.nDaysDiff(dueAt, this.nowSeconds)}d`;
    this.root.querySelector('.due-at').textContent = dueAtText;
  }

  attributeChangedCallback(name, _oldValue, newValue) {
    if (name === 'data-full-name') {
      this.setFullName(newValue);
    }
    if (name === 'data-frequency-days') {
      this.setFrequencyDays(newValue);
    }
    if (name === 'data-due-at') {
      this.setDueAt(newValue);
    }
  }
}

window.customElements.define('contact-item', ContactItem);

export default {};
