'use strict';

class CustomDialog extends HTMLElement {
  #ready = false;

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
    this.#ready = true;
  }

  showModal() {
    if (!this.#ready) {
      return;
    }

    this.root.querySelector('dialog').showModal();
  }

  close() {
    if (!this.#ready) {
      return;
    }

    this.root.querySelector('dialog').close();
  }
}


window.customElements.define('custom-dialog', CustomDialog);

export default {};
