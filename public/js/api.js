'use strict';

import auth from './auth.js';

async function fetchGithubToken(code) {
  try {
    const response = await fetch(`/auth/github/access_token?code=${code}`);
    return response.json();
  } catch (err) {
    console.error(err);
    return {};
  }
}

async function refreshGithubToken(refreshToken) {
  try {
    const response = await fetch(`/auth/github/refresh_token?refresh_token=${refreshToken}`);
    return response.json();
  } catch (err) {
    console.error(err);
    return {};
  }
}

async function fetchContactList() {
  const githubToken = auth.getGithubToken();
  const accessToken = githubToken.access_token;
  try {
    const contactList = await fetch('/api/v0/user/contacts', {
      headers: {'Authorization': `Bearer ${accessToken}`},
    });

    return contactList.json();
  } catch (err) {
    console.error(err);
    return {};
  }
}

export default {
	GITHUB_LOGIN_CALLBACK: '/auth/github/callback',
	fetchGithubToken,
  refreshGithubToken,
	fetchContactList,
};
