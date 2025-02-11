class GithubLogin extends HTMLElement {
  //static observedAttributes = ['contact_list_id'];

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
        console.log('Github login params: ', params);
        const client_id = params.github_client_id;
        // This will redirect the user to Github which will then redirect back to
        // /auth/github/callback.
        location.href = `https://github.com/login/oauth/authorize?client_id=${client_id}`;
      } catch (err) {
        console.error(err);
      }
    });
  }

  async fetchLoginParams() {
    const response = await fetch('/auth/github/login_params');
    return response.json();
  }

  disconnectedCallback() {
    console.log("Custom element removed from page.");
  }

  adoptedCallback() {
    console.log("Custom element moved to new page.");
  }

  attributeChangedCallback(name, oldValue, newValue) {
    console.log(`Attribute ${name} changed from: ${oldValue} to ${newValue}.`);
  }
}

export default window.customElements.define("github-login", GithubLogin);
