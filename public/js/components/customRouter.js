'use strict';

class CustomRouter extends HTMLElement {
  constructor() {
    super();

    window.addEventListener('popstate', (event) => {
      window.setTimeout(
        () => {
          this.updateRoutes(window.location.pathname, event.state || {});
        },
        0
      );
    });

    // TODO: Initialize state based on current path.
    const initialState = {};
    const initialLocalUrl = window.location.pathname + window.location.search;
    window.history.replaceState(initialState, '', initialLocalUrl);
  }

  connectedCallback() {
    const shadow = this.attachShadow({ mode: "open" });
    const slot = document.createElement("slot");
    shadow.appendChild(slot);

    this.updateRoutes(window.location.pathname, window.history.state || {});
  }

  updateRoutes(path, state) {
    this.querySelectorAll('custom-route').forEach((customRoute) => {
      customRoute.setAttribute('data-current-path', path);
      customRoute.setAttribute('data-route-state', JSON.stringify(state));
    });
  }
}

window.customElements.define('custom-router', CustomRouter);

export default {};
