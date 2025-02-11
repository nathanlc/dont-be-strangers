import './githubLogin.js';
import api from './api.js';
import storage from './storage.js';

const path = window.location.pathname;

if (path == api.GITHUB_LOGIN_CALLBACK) {
  const searchParams = new URLSearchParams(location.search);
  const code = searchParams.get('code');
  console.log('Github code: ', code);
  //const state = searchParams.get('state');

  const githubToken = await api.fetchGithubAccessToken(code);
  storage.storeGithubToken(githubToken);
	console.log('Github access token response: ', storage.storedGithubToken());
  location.href = '/';
}

// Do this in a better way.
if (path == '/') {
  const githubToken = storage.storedGithubToken();
  if (githubToken && githubToken.access_token) {
    const contactList = await api.fetchContactList();
    console.log(contactList);
  }
}
