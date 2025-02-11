const sessionStorage = window.sessionStorage;

function storeGithubToken(githubToken) {
  const githubTokenJson = JSON.stringify(githubToken);
  sessionStorage.setItem('github_token', githubTokenJson);
}

function storedGithubToken() {
  const githubTokenItem = sessionStorage.getItem('github_token');
  return JSON.parse(githubTokenItem);
}

export default {
	storeGithubToken,
	storedGithubToken,
};
