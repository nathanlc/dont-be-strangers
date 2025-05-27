'use strict';

import auth from '../auth.js';

class CustomRoute extends HTMLElement {
  // data-current-path and data-route-state are dynamically set by the router parent element.
  // data-route-state is stringified JSON.
  static observedAttributes = ['data-current-path', 'data-route-state'];

  #ready;
  #rendered;

  constructor() {
    super();
    // attributeChangedCallback is called before connectedCallback.
    // We need connectedCallback to run before the route is ready.
    this.#ready = false;
    // We do not want to append the child element multiple times.
    this.#rendered = false;
  }

  connectedCallback() {
    // console.log(`CustomRoute connectedCallback for path: ${this.getAttribute('data-path')}`);

    // TODO verify there is a parent custom-router element.

    this.#ready = true;
    this.handleRouteChange();
  }

  handleRouteChange() {
    const currentPath = this.getAttribute('data-current-path');
    if (!this.#ready || !currentPath) {
      return;
    }

    // console.log(`CustomRoute handleRouteChange for path: ${this.getAttribute('data-path')} and current path: ${this.getAttribute('data-current-path')}`);

    if (currentPath === this.getAttribute('data-path')) {
      // console.log(`CustomRoute for path ${this.getAttribute('data-path')} ACTIVATED.`);
      if (this.getAttribute('data-auth-required') === 'true') {
        if (!auth.isAuthenticated()) {
          (async () => {
            await auth.authenticateGithub();
          })();
        }
      }

      if (!this.#rendered) {
        const childElementName = this.getAttribute('data-element');
        const childElement = document.createElement(childElementName);
        this.appendChild(childElement);
        this.#rendered = true;
      } else {
        console.log(`CustomRoute for path ${this.getAttribute('data-path')} already rendered.`);
      }
    } else {
      // console.log(`CustomRoute for path ${this.getAttribute('data-path')} DEACTIVATED.`);
      this.innerHTML = '';
      this.#rendered = false;
    }
  }

  attributeChangedCallback(name, _oldValue, _newValue) {
    if (name === 'data-current-path') {
      this.handleRouteChange();
    }
    //if (name === 'data-route-state') {
    //  console.log('New data-route-state:', newValue);
    //}
  }
}

window.customElements.define('custom-route', CustomRoute);

export default {};
