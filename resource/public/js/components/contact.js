'use strict';

import api from '../api.js';
import auth from '../auth.js';
import routing from '../routing.js';
import time from '../time.js';

class ContactList extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    this.innerHTML = `
      <div>
        <h3>Contacts</h3>
        <div>
          <add-contact-button></add-contact-button>
        </div>
        <ul></ul>
      </div>
    `;

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
    const ul = this.querySelector('ul');
    ul.innerHTML = '';

    contacts.sort((a, b) => a.due_at - b.due_at);

    contacts.forEach((contact) => {
      const contactItem = document.createElement('contact-item');
      // Appending before setting attributes because:
      // - ContactItem.connectedCallback will only be triggered once added to the DOM
      // - ContactItem.attributeChangedCallback can only work if the innerHTML is defined (happens inside connectedCallback)
      ul.appendChild(contactItem);
      contactItem.setAttribute('data-id', contact.id);
      contactItem.setAttribute('data-full-name', contact.full_name);
      contactItem.setAttribute('data-frequency-days', contact.frequency_days);
      contactItem.setAttribute('data-due-at', contact.due_at);
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

  #ready = false;

  constructor() {
    super();
  }

  connectedCallback() {
    this.innerHTML = `
      <li>
        <span class="full-name"></span>
        <span class="frequency-days"></span>
        <span class="due-at"></span>
        <button class="contacted-action">✔️</button>
        <span class="contacted-status contacted-pending display-none">⏳</span>
        <span class="contacted-status contacted-success display-none">✅</span>
        <span class="contacted-status contacted-error display-none">🚫</span>
      </li>
    `;
    this.#ready = true;

    this.querySelector('button.contacted-action')
      .addEventListener('click', (_) => this.handleContactedAction());
  }

  setFullName(fullName) {
    this.querySelector('.full-name').textContent = fullName;
  }

  setFrequencyDays(frequencyDays) {
    this.querySelector('.frequency-days').textContent = `(${frequencyDays}d 🕔)`;
  }

  setDueAt(dueAt) {
    const dueAtText = `${time.nDaysDiff(dueAt, time.nowSeconds())}d`;
    this.querySelector('.due-at').textContent = dueAtText;
  }

  setContactedRequestStatus(status) {
    console.log(`setContactedRequestStatus: ${status}`);
    this.querySelectorAll('.contacted-status').forEach((el) => {
      el.classList.add('display-none');
    });

    const statusEl = this.querySelector(`.contacted-status.contacted-${status.toLowerCase()}`);
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
    if (this.#ready === false) {
      return;
    }

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
