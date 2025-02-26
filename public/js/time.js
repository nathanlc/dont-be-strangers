'use strict';

const SECONDS_PER_DAY = 86_400;

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

/*
 * @param {number} timeInSeconds
 * @param {number=} from - Defaults to now in seconds.
 * @returns {number} Number of days (ceiled).
 */
function nDaysDiff(timeInSeconds, from = null) {
  if (from === null) {
    from = nowSeconds();
  }

  // TODO: Test this both when date is after or passed.
  return Math.ceil((from - timeInSeconds) / SECONDS_PER_DAY);
}

export default {
  nowSeconds,
  nDaysDiff,
};
