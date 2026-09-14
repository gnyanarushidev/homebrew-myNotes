import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";

export const database = new PGlite();
await database.exec("create schema auth; create table auth.users(id uuid primary key); create role anon; create role authenticated; create role service_role bypassrls;");
await database.exec(await readFile(new URL("../../supabase/migrations/002_cloud_storage.sql", import.meta.url), "utf8"));
const objects = new Map();
export async function resetCloud(ids) {
  objects.clear();
  await database.exec("truncate cloud_references, cloud_objects, cloud_notebooks, cloud_operations, cloud_accounts, auth.users cascade");
  for (const id of new Set(ids)) await database.query("insert into auth.users(id) values ($1)", [id]);
}
export async function addCloudUser(id) { await database.query("insert into auth.users(id) values ($1) on conflict do nothing", [id]); }

export async function cloudRequest(request, response, url, raw) {
  const send = (status, value) => { response.writeHead(status, { "Content-Type": "application/json" }); response.end(JSON.stringify(value)); };
  if (url.pathname.startsWith("/test-bucket/")) {
    const key = decodeURIComponent(url.pathname.slice("/test-bucket/".length));
    const versions = objects.get(key) ?? new Map();
    if (request.method === "PUT") {
      const id = randomUUID(); versions.set(id, { bytes: raw, type: request.headers["content-type"], encoding: request.headers["content-encoding"] }); objects.set(key, versions);
      response.writeHead(200, { "x-amz-version-id": id, ETag: '"test-etag"', "Access-Control-Allow-Origin": "*" }); response.end(); return true;
    }
    const id = url.searchParams.get("versionId") ?? [...versions.keys()].at(-1);
    if (request.method === "DELETE") { versions.delete(id); response.writeHead(204); response.end(); return true; }
    if (request.method === "OPTIONS") { response.writeHead(200, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,PUT", "Access-Control-Allow-Headers": "*" }); response.end(); return true; }
    const file = versions.get(id);
    if (!file) { response.writeHead(404, { "Content-Type": "application/xml" }); response.end("<Error><Code>NoSuchKey</Code><Message>Missing test object</Message></Error>"); return true; }
    response.writeHead(200, { "Content-Type": file.type ?? "application/octet-stream", "Content-Length": file.bytes.length, "x-amz-version-id": id, "Access-Control-Allow-Origin": "*", ...(file.encoding ? { "Content-Encoding": file.encoding } : {}) }); response.end(file.bytes); return true;
  }
  if (!url.pathname.startsWith("/rest/v1/cloud_") && !url.pathname.startsWith("/rest/v1/rpc/cloud_")) return false;
  if (request.headers.apikey !== "sb_secret_test") { send(403, { message: "Forbidden" }); return true; }
  const body = raw.length ? JSON.parse(raw.toString()) : {};
  try {
    let rows;
    if (url.pathname === "/rest/v1/rpc/cloud_usage") { send(200, (await database.query("select cloud_usage($1) result", [body.p_owner])).rows[0].result); return true; }
    if (url.pathname === "/rest/v1/rpc/cloud_commit") {
      const keys = ["p_owner", "p_id", "p_operation", "p_hash", "p_base", "p_manifest", "p_deleted", "p_keep_both", "p_conflict_id", "p_conflict_manifest"];
      const result = await database.query("select cloud_commit($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as result", keys.map(k => body[k]));
      send(200, result.rows[0].result); return true;
    }
    if (url.pathname === "/rest/v1/rpc/cloud_cleanup_candidates") {
      rows = (await database.query("select * from cloud_cleanup_candidates($1)", [body.p_owner])).rows;
      send(200, rows); return true;
    }
    const table = url.pathname.split("/").pop();
    if (!["cloud_accounts", "cloud_notebooks", "cloud_operations", "cloud_objects", "cloud_references"].includes(table)) throw new Error("Unknown fixture table");
    const identifier = value => { if (!/^[a-z_][a-z0-9_]*$/.test(value)) throw new Error("Invalid column"); return `"${value}"`; };
    const fields = url.searchParams.get("select") ?? "*";
    const select = fields === "*" ? "*" : fields.split(",").map(identifier).join(",");
    const params = [], filters = [];
    for (const [column, expression] of url.searchParams) {
      if (["select", "order", "limit", "offset"].includes(column)) continue;
      if (expression.startsWith("in.(")) {
        const values = expression.slice(4, -1).split(",").map(value => value.replace(/^"|"$/g, ""));
        const placeholders = values.map(value => { params.push(value); return `$${params.length}`; });
        filters.push(`${identifier(column)} in (${placeholders.join(",")})`); continue;
      }
      const dot = expression.indexOf("."), operator = { eq: "=", gt: ">", lte: "<=" }[expression.slice(0, dot)];
      if (!operator) throw new Error("Unsupported fixture filter");
      params.push(expression.slice(dot + 1)); filters.push(`${identifier(column)} ${operator} $${params.length}`);
    }
    const where = filters.length ? ` where ${filters.join(" and ")}` : "";
    if (request.method === "POST") {
      const columns = Object.keys(body);
      rows = (await database.query(`insert into ${table} (${columns.map(identifier).join(",")}) values (${columns.map((_, i) => `$${i + 1}`).join(",")}) returning ${select}`, columns.map(k => body[k]))).rows;
    } else if (request.method === "DELETE") rows = (await database.query(`delete from ${table}${where} returning ${select}`, params)).rows;
    else if (request.method === "PATCH") {
      const sets = Object.entries(body).map(([key, value]) => { params.push(value); return `${identifier(key)}=$${params.length}`; });
      rows = (await database.query(`update ${table} set ${sets.join(",")}${where} returning ${select}`, params)).rows;
    }
    else {
      const order = url.searchParams.get("order")?.split(",").map(value => { const [name, direction] = value.split("."); return `${identifier(name)} ${direction === "desc" ? "desc" : "asc"}`; }).join(",");
      const limit = Math.min(Number(url.searchParams.get("limit") ?? 1000), 1000), offset = Number(url.searchParams.get("offset") ?? 0);
      rows = (await database.query(`select ${select} from ${table}${where}${order ? ` order by ${order}` : ""} limit ${limit} offset ${offset}`, params)).rows;
    }
    if (request.headers.accept?.includes("application/vnd.pgrst.object+json")) {
      if (rows.length !== 1) send(406, { code: "PGRST116", details: `The result contains ${rows.length} rows` }); else send(200, rows[0]);
    } else send(200, rows);
  } catch (error) { send(400, { code: error.code ?? "FIXTURE", message: error.message }); }
  return true;
}
