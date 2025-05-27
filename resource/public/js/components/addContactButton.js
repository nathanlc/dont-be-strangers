'use strict';

class AddContactButton extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    this.innerHTML = `
      <div>
        <button>Add Contact</button>
        <custom-dialog>
          <h3 slot="title">Add contact</h3>
          <add-contact-form></add-contact-form>
        </custom-dialog>
      </div>
    `;

    this.querySelector('button').addEventListener('click', async (event) => {
      event.preventDefault();

      const customDialog = this.querySelector('custom-dialog');
      customDialog.showModal();
      this.querySelector('add-contact-form').onSuccess(() => {
        customDialog.close();
        window.location.reload();
      });
    });
  }
}


window.customElements.define('add-contact-button', AddContactButton);

export default {};
