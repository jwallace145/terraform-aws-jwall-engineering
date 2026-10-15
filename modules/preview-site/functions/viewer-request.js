// Viewer-request function for preview-site distributions.
// Maps `pr-<n>.preview.<site>` to the `pr-<n>/` folder under the distribution's
// origin path (`/previews`), so `https://pr-12.preview.site/docs/` serves
// `s3://bucket/previews/pr-12/docs/index.html`.
var LABEL = /^pr-\d+$/;

function handler(event) {
  var request = event.request;
  var host = request.headers.host ? request.headers.host.value : '';
  var label = host.split('.')[0];

  if (!LABEL.test(label)) {
    return {
      statusCode: 404,
      statusDescription: 'Not Found',
      headers: { 'content-type': { value: 'text/plain' } },
      body: 'Not Found',
    };
  }

  var uri = request.uri;
  if (uri.endsWith('/')) {
    uri = uri + 'index.html';
  } else if (!uri.includes('.')) {
    uri = uri + '/index.html';
  }

  request.uri = '/' + label + uri;
  return request;
}
