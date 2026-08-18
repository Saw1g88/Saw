let config = {
  username: $argument.username,
  token: $argument.token,
};

const username = $request.url.match(
  /https:\/\/(?:raw|gist)\.githubusercontent\.com\/([^\/]+)\//
)[1];

// 只对你自己的私库附加 Authorization
if (username == config.username) {
  console.log(`ACCESSING PRIVATE REPO: ${$request.url}`);
  $done({
    headers: { ...$request.headers, Authorization: `token ${config.token}` }
  });
} else {
  $done({});
}
