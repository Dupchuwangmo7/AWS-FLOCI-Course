// usms-edge-viewer-request
// CloudFront trigger point: viewer-request. Runs on every request, before the cache.
// Returns the request object to continue, or a response object to stop.

const AUTH_HEADER = 'x-usms-student';
const PROTECTED_PREFIX = '/transcripts/';

export const handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;

  // 1. Normalise the URI so one object has one cache entry.
  request.uri = request.uri.toLowerCase();

  // 2. Anything outside /transcripts/ is not this function's business.
  if (!request.uri.startsWith(PROTECTED_PREFIX)) {
    return request;
  }

  // 3. A header value is an ARRAY of {key, value} objects - note the [0].
  const studentHeader = headers[AUTH_HEADER];
  const studentId = studentHeader && studentHeader[0] && studentHeader[0].value;

  if (!studentId) {
    return {
      status: '403',
      statusDescription: 'Forbidden',
      headers: {
        'content-type': [{ key: 'Content-Type', value: 'application/json' }],
        'cache-control': [{ key: 'Cache-Control', value: 'no-store' }],
        'x-usms-edge': [{ key: 'X-USMS-Edge', value: 'viewer-request-deny' }]
      },
      body: JSON.stringify({ message: 'transcript access requires an authenticated session' })
    };
  }

  // 4. Stamp the request so origin-response can see we ran.
  request.headers['x-usms-edge'] = [
    { key: 'X-USMS-Edge', value: `viewer-request-allow;student=${studentId.toLowerCase()}` }
  ];

  return request;
};
