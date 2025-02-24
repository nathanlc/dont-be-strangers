'use strict';

import api from './api.js';
import routing from './routing.js';

const storage = window.sessionStorage;
const GITHUB_TOKEN = 'github_token';

function now_seconds() {
  return Math.floor(Date.now() / 1000);
}

function getGithubToken() {
  const githubTokenItem = storage.getItem(GITHUB_TOKEN);
  return JSON.parse(githubTokenItem);
}

function removeGithubToken() {
  storage.removeItem(GITHUB_TOKEN);
}

function setGithubToken(githubToken) {
  // Github token doesn't include an "issued_at" field.
  githubToken.issued_at = now_seconds();
  const githubTokenJson = JSON.stringify(githubToken);
  storage.setItem(GITHUB_TOKEN, githubTokenJson);
}

async function fetchGithubToken(code, state) {
  try {
    const token = await api.fetchGithubToken(code, state);
    setGithubToken(token);
    return token;
  } catch (err) {
    console.error(err);
    return {};
  }
}

async function refreshGithubToken() {
  const githubToken = getGithubToken();
  if (!githubToken || !githubToken.refresh_token) {
    console.error('Expected a refresh token to exist. GithubToken: ', githubToken);
    return {};
  }

  const refreshToken = githubToken.refresh_token;

  try {
    const token = await api.refreshGithubToken(refreshToken);
    setGithubToken(token);
    return token;
  } catch (err) {
    console.error('Error while refreshing github token.', err);
    throw err;
  }
}

function isTokenValid(githubToken) {
  return githubToken && githubToken.issued_at && githubToken.expires_in;
}

function isAccessTokenValid(githubToken) {
  return isTokenValid(githubToken) && (githubToken.issued_at + githubToken.expires_in) > now_seconds();
}

function isAuthenticated() {
  const githubToken = getGithubToken();

  return isAccessTokenValid(githubToken);
}

async function authenticateGithub() {
  const githubToken = getGithubToken();

  if (!githubToken || !isTokenValid(githubToken)) {
    routing.push('/', {});
    return;
  }

  if (!isAccessTokenValid(githubToken)) {
    try {
      await refreshGithubToken();
    } catch (err) {
      console.error('Failed to refresh token. Redirecting to "/"', err);
      routing.push('/', {});
    }
  }

  return;
}

export default {
  getGithubToken,
  removeGithubToken,
  fetchGithubToken,
  isAuthenticated,
  authenticateGithub,
};
