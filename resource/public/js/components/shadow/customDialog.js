'use strict';

class CustomDialog extends HTMLElement {
  constructor() {
    super();
    this.root = null;
  }

  connectedCallback() {
    this.root = this.attachShadow({ mode: 'open' });
    this.root.innerHTML = `
      <dialog class="custom-dialog">
        <span class="close-button">X</span>
        <slot name="title">[[Title]]</slot>
        <slot></slot>
      </dialog>
    `;

    this.root.querySelector('.close-button').addEventListener('click', async (_event) => {
      this.root.querySelector('dialog').close();
    });
  }

  showModal() {
    this.root.querySelector('dialog')?.showModal();
  }

  close() {
    this.root.querySelector('dialog')?.close();
  }
}


window.customElements.define('custom-dialog', CustomDialog);

export default {};
