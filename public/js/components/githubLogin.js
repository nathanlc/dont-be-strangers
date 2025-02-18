'use strict';

class GithubLogin extends HTMLElement {
  constructor() {
    super();
    const template = document.getElementById(
      "template-github-login",
    ).content;
    this.root = this.attachShadow({ mode: "open" });
    this.root.appendChild(template.cloneNode(true));
  }

  connectedCallback() {
    const button = this.root.querySelector('button');

    button.addEventListener('click', async (event) => {
      event.preventDefault();

      try {
        const params = await this.fetchLoginParams();
        const client_id = params.github_client_id;
        const state = params.state;
        // This will redirect the user to Github which will then redirect back to
        // /auth/github/callback.
        window.location.href = `https://github.com/login/oauth/authorize?client_id=${client_id}&state=${state}`;
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
