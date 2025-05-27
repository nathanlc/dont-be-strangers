'use strict';

import api from '../api.js';

class GithubLogin extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    this.innerHTML = `
      <div>
        <button type="button">Login with GitHub</button>
      </div>
    `;
    const button = this.querySelector('button');

    button.addEventListener('click', async (event) => {
      event.preventDefault();

      try {
        const params = await this.fetchLoginParams();
        const client_id = params.github_client_id;
        const state = params.state;
        const redirect_uri = encodeURIComponent(window.location.origin + api.GITHUB_LOGIN_CALLBACK);
        // This will redirect the user to Github which will then redirect back to /auth/github/callback.
        window.location.href = `https://github.com/login/oauth/authorize?client_id=${client_id}&state=${state}&redirect_uri=${redirect_uri}`;
      } catch (err) {
        console.error(err);
      }
    });
  }

  async fetchLoginParams() {
    const response = await fetch('/auth/github/login_params');
    return response.json();
  }
}

export default window.customElements.define("github-login", GithubLogin);
