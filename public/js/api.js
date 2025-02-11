import storage from './storage.js';

async function fetchGithubAccessToken(code) {
  try {
    const response = await fetch(`/auth/github/access_token?code=${code}`);
    return response.json();
  } catch (err) {
    console.error(err);
    return {};
  }
}

async function fetchContactList() {
  const githubToken = storage.storedGithubToken();
  const accessToken = githubToken.access_token;
  const contactList = await fetch('/api/v0/user/contacts', {
    headers: {'Authorization': `Bearer ${accessToken}`},
  });

  return contactList.json();
}

export default {
	GITHUB_LOGIN_CALLBACK: '/auth/github/callback',
	fetchGithubAccessToken,
	fetchContactList,
};
