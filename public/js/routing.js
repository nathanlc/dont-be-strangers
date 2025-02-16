'use strict';

function push(url, state) {
  window.history.pushState(state, '', url);
  window.dispatchEvent(new Event('popstate', state));
}

export default {
  push,
};
