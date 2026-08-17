/*
 * 配合 GitHub.plugin 使用
 * 作用：当请求 URL 命中 username/repo 前缀时，
 *      删除原有 Authorization 头，注入 token；
 *      同时把 Accept-Language 统一改成 en-us
 */

const { username, token } = $argument;
const url = $request.url;
const headers = $request.headers || {};

// 统一改 Accept-Language
headers["Accept-Language"] = "en-us";
headers["accept-language"] = "en-us";

// 只有命中 raw/gist.githubusercontent.com/<username>/... 才注入 token
const pattern = new RegExp(
  `^https?:\\/\\/(raw|gist)\\.githubusercontent\\.com\\/${username}(\\/|$)`
);

if (pattern.test(url)) {
  delete headers["Authorization"];
  delete headers["authorization"];
  headers["Authorization"] = `token ${token}`;
}

$done({ headers });
