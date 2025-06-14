'use strict';

import auth from './auth.js';
import time from './time.js';

/**
 * @enum {string}
 */
const requestStatus = {
  Idle: 'Idle',
  Pending: 'Pending',
  Success: 'Success',
  Error: 'Error',
};

async function fetchGithubToken(code, state) {
  try {
    const response = await fetch(`/auth/github/access_token?code=${code}&state=${state}`);
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

  return fetch('/api/v0/user/contacts', {
    headers: { 'Authorization': `Bearer ${accessToken}` },
  });
}

/**
 * @param {number} contact_id
 * @returns {Promise<Response>}
 */
async function patchContactContactedAt(contact_id) {
  const githubToken = auth.getGithubToken();
  const accessToken = githubToken.access_token;

  return fetch(`/api/v0/user/contacts/${contact_id}`, {
    method: 'PATCH',
    body: JSON.stringify({ contacted_at: time.nowSeconds() }),
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  });
}

/**
 * @param {{full_name: string, frequency_days: number}} contact
 * @returns {Promise<Response>}
 */
async function createContact(contact) {
  const githubToken = auth.getGithubToken();
  const accessToken = githubToken.access_token;

  return fetch(`/api/v0/user/contacts`, {
    method: 'POST',
    body: JSON.stringify(contact),
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  });
}

export default {
  requestStatus,
  GITHUB_LOGIN_CALLBACK: '/auth/github/callback',
  fetchGithubToken,
  refreshGithubToken,
  fetchContactList,
  createContact,
  patchContactContactedAt,
};
