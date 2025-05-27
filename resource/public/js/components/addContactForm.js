'use strict';

import api from '../api.js';

class AddContactForm extends HTMLElement {
  successCallback = () => { console.log('AddContactForm submitted successfully.') };

  constructor() {
    super();
  }

  connectedCallback() {
    this.innerHTML = `
      <form>
        <div>
          <label for="full-name-input">Full name</label>
          <input id="full-name-input" type="text" placeholder="John Doe" name="full_name" value="" required/>
        </div>
        <div>
          <label for="frequency-days-input">Frequency days</label>
          <input id="frequency-days-input" type="number" name="frequency_days" value="1" required/>
        </div>
        <div>
          <button type="submit">Save contact</button>
        </div>
      </form>
    `;

    this.querySelector('form').addEventListener('submit', async (event) => {
      event.preventDefault();

      const formData = new FormData(event.target);
      const payload = Object.fromEntries(formData.entries());

      const response = await api.createContact(payload);
      if (response.ok) {
        this.successCallback();
      } else {
        // TODO: Trigger an onFailure + add error somewhere in form.
        console.err(response);
      }
    });
  }

  onSuccess(callback) {
    this.successCallback = callback;
  }
}


window.customElements.define('add-contact-form', AddContactForm);

export default {};
