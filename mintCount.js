const { Redis } = require('@upstash/redis');

function getRedisConfig() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;
  return { url, token };
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const config = getRedisConfig();
  if (!config) {
    return res.status(500).json({
      error: 'Redis not configured',
      hint: 'Missing KV_REST_API_URL or KV_REST_API_TOKEN env vars. Set them in Vercel Project Settings.'
    });
  }

  const redis = new Redis(config);

  try {
    if (req.method === 'GET') {
      return await handleGet(req, res, redis);
    }
    if (req.method === 'POST') {
      return await handlePost(req, res, redis);
    }
    return res.status(405).json({ error: 'Method not allowed' });
  } catch (e) {
    console.error('mintCount API Error:', e);
    return res.status(500).json({ error: e.message });
  }
};

async function handleGet(req, res, redis) {
  const tokenKey = 'tokens_data';
  const runKey = 'mint_running';
  const doneKey = 'mint_done';

  let tokenList = await redis.get(tokenKey);
  if (!tokenList) tokenList = [];
  const running = (await redis.get(runKey)) || 0;
  const done = (await redis.get(doneKey)) || 0;

  return res.status(200).json({
    list: tokenList,
    mint_running: Number(running),
    mint_done: Number(done)
  });
}

async function handlePost(req, res, redis) {
  const body = req.body || {};
  const type = body.type;
  const num = body.num;
  const tokenInfo = body.tokenInfo;

  const tokenKey = 'tokens_data';
  const runKey = 'mint_running';
  const doneKey = 'mint_done';

  // 1. 保存代币记录（只要有 tokenInfo 就保存，不管 type 是什么）
  if (tokenInfo && tokenInfo.a) {
    let tokenList = (await redis.get(tokenKey)) || [];
    var exists = tokenList.some(function(t) { return t.a === tokenInfo.a; });
    if (!exists) {
      tokenList.push(tokenInfo);
      await redis.set(tokenKey, tokenList);
    }
  }

  // 2. 更新计数（num 有值时直接 set，兼容 index.html 传绝对值的方式）
  if (type === 'running' && num !== undefined) {
    await redis.set(runKey, Number(num));
  } else if (type === 'done' && num !== undefined) {
    await redis.set(doneKey, Number(num));
  }

  return res.status(200).json({ success: true });
}
