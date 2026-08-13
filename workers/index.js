const ALLOWED_IMAGE_HOSTS = ['assets.hardcover.app'];

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (request.method === 'GET' && url.pathname === '/img') {
      return handleImageProxy(url);
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    return handleGraphql(request);
  },
};

async function handleImageProxy(url) {
  const target = url.searchParams.get('url');
  if (!target) {
    return new Response('Missing url', { status: 400, headers: corsHeaders });
  }

  let imageUrl;
  try {
    imageUrl = new URL(target);
  } catch (_) {
    return new Response('Invalid url', { status: 400, headers: corsHeaders });
  }

  if (!ALLOWED_IMAGE_HOSTS.includes(imageUrl.host)) {
    return new Response('Forbidden host', { status: 403, headers: corsHeaders });
  }

  const cache = caches.default;
  const cacheKey = new Request(imageUrl.toString());
  const cached = await cache.match(cacheKey);
  if (cached) {
    const resp = new Response(cached.body, cached);
    resp.headers.set('Access-Control-Allow-Origin', '*');
    return resp;
  }

  try {
    const upstream = await fetch(imageUrl.toString());
    if (!upstream.ok) {
      return new Response(upstream.statusText, { status: upstream.status, headers: corsHeaders });
    }

    const headers = new Headers(upstream.headers);
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Cache-Control', 'public, max-age=604800, immutable');

    const body = await upstream.arrayBuffer();
    const response = new Response(body, { status: 200, headers });

    const copy = new Response(body, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
    copy.headers.set('Cache-Control', 'public, max-age=604800, immutable');
    await cache.put(cacheKey, copy);

    return response;
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  }
}

async function handleGraphql(request) {
  const authHeader = request.headers.get('Authorization') || '';

  try {
    const upstream = await fetch('https://api.hardcover.app/v1/graphql', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': authHeader,
      },
      body: request.body,
    });

    const resp = new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: upstream.headers,
    });

    resp.headers.set('Access-Control-Allow-Origin', '*');
    resp.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    resp.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    return resp;
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 502,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  }
}
