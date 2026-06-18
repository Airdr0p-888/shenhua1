import { kv } from '@vercel/kv';
export const runtime = 'edge';

// 读取代币列表 + 铸造计数
export async function GET(req) {
  const { searchParams } = new URL(req.url);
  const project = searchParams.get('project') || "";

  // 分开两套存储键名
  const tokenKey = project === "shenhua" ? "tokens_data_shenhua" : "tokens_data";
  const runKey = project === "shenhua" ? "mint_running_shenhua" : "mint_running";
  const doneKey = project === "shenhua" ? "mint_done_shenhua" : "mint_done";

  // 读取代币数组
  let tokenList = await kv.get(tokenKey);
  if (!tokenList) tokenList = [];
  // 读取计数
  const running = await kv.get(runKey) || 0;
  const done = await kv.get(doneKey) || 0;

  return Response.json({
    list: tokenList,
    mint_running: Number(running),
    mint_done: Number(done)
  });
}

// 写入数据：新增代币 / 修改计数
export async function POST(req) {
  const { type, num, tokenInfo, project = "" } = await req.json();
  const tokenKey = project === "shenhua" ? "tokens_data_shenhua" : "tokens_data";
  const runKey = project === "shenhua" ? "mint_running_shenhua" : "mint_running";
  const doneKey = project === "shenhua" ? "mint_done_shenhua" : "mint_done";

  // 1. 更新铸造计数
  if(type === 'running'){
    await kv.set(runKey, Number(num));
    return Response.json({success:true});
  }
  if(type === 'done'){
    await kv.set(doneKey, Number(num));
    return Response.json({success:true});
  }

  // 2. 新增一条代币记录存入数组
  if(tokenInfo){
    let tokenList = await kv.get(tokenKey) || [];
    tokenList.push(tokenInfo);
    await kv.set(tokenKey, tokenList);
    return Response.json({success:true});
  }
}