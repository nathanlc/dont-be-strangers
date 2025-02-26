'use strict';

import api from '../api.js';
import auth from '../auth.js';
import routing from '../routing.js';

class ContactList extends HTMLElement {
  //static observedAttributes = ['contact_list_id'];

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
      contactItem.setAttribute('data-full-name', contact.full_name);
      contactItem.setAttribute('data-frequency-days', contact.frequency_days);
      contactItem.setAttribute('data-due-at', contact.due_at);
      ul.appendChild(contactItem);
    });
  }
}

window.customElements.define('contact-list', ContactList);

export default {};
