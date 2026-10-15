// Viewer-request function for static-site distributions.
// Rewrites directory requests to their index document so that S3 (which has no
// notion of a directory index) serves `/dir/index.html` for `/dir/` and `/dir`.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else if (!uri.includes('.')) {
    request.uri = uri + '/index.html';
  }

  return request;
}
