'use strict';

import api from '../api.js';
import auth from '../auth.js';
import routing from '../routing.js';
import time from '../time.js';

class ContactList extends HTMLElement {
  constructor() {
    super();
    const template = document.getElementById(
      "template-contact-list",
    ).content;
    this.root = this.attachShadow({ mode: "open" });
    this.root.appendChild(template.cloneNode(true));
  }

  connectedCallback() {
    // TODO: move that to custom-route.
    if (!auth.isAuthenticated()) {
      routing.push('/', {});
    }

    (async () => {
      const response = await api.fetchContactList();
      if (response.status === 401) {
        // Access token is invalid, remove it and redirect to login.
        auth.removeGithubToken();
        routing.push('/', {});
        return;
      }

      const contactList = await response.json();
      this.setContactList(contactList);
    })();
  }

  setContactList(contacts) {
    const ul = this.root.querySelector('ul');
    ul.innerHTML = '';

    contacts.sort((a, b) => a.due_at - b.due_at);

    contacts.forEach((contact) => {
      const contactItem = document.createElement('contact-item');
      contactItem.setAttribute('data-id', contact.id);
      contactItem.setAttribute('data-full-name', contact.full_name);
      contactItem.setAttribute('data-frequency-days', contact.frequency_days);
      contactItem.setAttribute('data-due-at', contact.due_at);
      ul.appendChild(contactItem);
    });
  }
}

class ContactItem extends HTMLElement {
  static observedAttributes = [
    'data-id',
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

    this.root.querySelector('button.contacted-action')
      .addEventListener('click', (_) => this.handleContactedAction());
  }

  setFullName(fullName) {
    this.root.querySelector('.full-name').textContent = fullName;
  }

  setFrequencyDays(frequencyDays) {
    this.root.querySelector('.frequency-days').textContent = `(${frequencyDays}d 🕔)`;
  }

  setDueAt(dueAt) {
    const dueAtText = `${time.nDaysDiff(dueAt, time.nowSeconds())}d`;
    this.root.querySelector('.due-at').textContent = dueAtText;
  }

  setContactedRequestStatus(status) {
    console.log(`setContactedRequestStatus: ${status}`);
    this.root.querySelectorAll('.contacted-status').forEach((el) => {
      el.classList.add('display-none');
    });

    const statusEl = this.root.querySelector(`.contacted-status.contacted-${status.toLowerCase()}`);
    if (statusEl) {
      statusEl.classList.remove('display-none');
    }
  }

  async handleContactedAction() {
    const id = this.getAttribute('data-id');

    this.setContactedRequestStatus(api.requestStatus.Pending);
    try {
      const response = await api.patchContactContactedAt(id);
      if (response.ok) {
        this.setContactedRequestStatus(api.requestStatus.Success);
        const updatedContact = await response.json();
        this.setAttribute('data-due-at', updatedContact.due_at);
      } else {
        this.setContactedRequestStatus(api.requestStatus.Error);
      }
    } catch (err) {
      this.setContactedRequestStatus(api.requestStatus.Error);
      console.error(err);
    }
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
window.customElements.define('contact-list', ContactList);

export default {};
