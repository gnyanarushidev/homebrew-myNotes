import nextEnv from "@next/env";
import { S3Client, HeadBucketCommand, GetBucketCorsCommand, GetBucketAclCommand, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, ListObjectVersionsCommand } from "@aws-sdk/client-s3";
import { randomUUID } from "node:crypto";
import { gzipSync, gunzipSync } from "node:zlib";
nextEnv.loadEnvConfig(process.cwd(), false, { info() {}, error() {} });
const env = process.env;
const required = ["APP_URL", "NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_SECRET_KEY", "ADMIN_EMAIL", "B2_ENDPOINT", "B2_REGION", "B2_BUCKET_NAME", "B2_APPLICATION_KEY_ID", "B2_APPLICATION_KEY"];
const missing = required.filter(key => !env[key]);
console.log(process.argv.includes("--probe") ? "Cloud configuration check with temporary B2 object probe" : "Read-only cloud configuration check");
if (missing.length) { console.log(`Missing settings: ${missing.join(", ")}`); process.exitCode = 1; }
if (env.NEXT_PUBLIC_SUPABASE_URL && env.SUPABASE_SECRET_KEY) {
  const response = await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/cloud_notebooks?select=id&limit=0`, { headers: { apikey: env.SUPABASE_SECRET_KEY, Authorization: `Bearer ${env.SUPABASE_SECRET_KEY}` }, signal: AbortSignal.timeout(15000) });
  console.log(response.ok ? "Supabase metadata table: accessible" : `Supabase metadata table: HTTP ${response.status}; apply 002_cloud_storage.sql and check the project/key.`);
  if (!response.ok) process.exitCode = 1;
}
if (["B2_ENDPOINT", "B2_REGION", "B2_BUCKET_NAME", "B2_APPLICATION_KEY_ID", "B2_APPLICATION_KEY"].every(key => env[key])) {
  const client = new S3Client({ endpoint: env.B2_ENDPOINT, region: env.B2_REGION, forcePathStyle: true, maxAttempts: 1, credentials: { accessKeyId: env.B2_APPLICATION_KEY_ID, secretAccessKey: env.B2_APPLICATION_KEY }, requestChecksumCalculation: "WHEN_REQUIRED" });
  try {
    await client.send(new HeadBucketCommand({ Bucket: env.B2_BUCKET_NAME }), { abortSignal: AbortSignal.timeout(15000) }); console.log("B2 bucket: reachable");
    try { const acl = await client.send(new GetBucketAclCommand({ Bucket: env.B2_BUCKET_NAME })); const publicRead = acl.Grants?.some(grant => grant.Grantee?.URI?.endsWith("/AllUsers")); console.log(`B2 access: ${publicRead ? "PUBLIC — change this bucket to private before using notebooks" : "private ACL"}`); if (publicRead) process.exitCode = 1; }
    catch (error) { console.log(`B2 privacy check: ${error.name}; confirm Private in the bucket console.`); }
    try { const cors = await client.send(new GetBucketCorsCommand({ Bucket: env.B2_BUCKET_NAME })); console.log(`B2 CORS: ${cors.CORSRules?.some(rule => rule.AllowedOrigins?.includes(env.APP_URL) && rule.AllowedMethods?.includes("PUT") && rule.AllowedMethods?.includes("GET")) ? "application GET/PUT rule found" : "configure the exact application origin with GET and PUT"}`); }
    catch (error) { console.log(`B2 CORS: ${error.name}; configure application GET/PUT access in the bucket console.`); process.exitCode = 1; }
    if (process.argv.includes("--probe")) {
      const key = `staging/readiness/${randomUUID()}.json.gz`;
      const original = Buffer.from('{"probe":"mynotes-storage-readiness"}');
      let version;
      try {
        const put = await client.send(new PutObjectCommand({ Bucket: env.B2_BUCKET_NAME, Key: key, Body: gzipSync(original), ContentType: "application/json", ContentEncoding: "gzip" }), { abortSignal: AbortSignal.timeout(15000) });
        version = put.VersionId;
        if (!version) throw new Error(`Missing version ID; inspect the temporary object ${key}`);
        const get = await client.send(new GetObjectCommand({ Bucket: env.B2_BUCKET_NAME, Key: key, VersionId: version }), { abortSignal: AbortSignal.timeout(15000) });
        const bytes = await get.Body.transformToByteArray();
        if (!gunzipSync(bytes).equals(original)) throw new Error("Probe content did not round-trip correctly");
        const versions = await client.send(new ListObjectVersionsCommand({ Bucket: env.B2_BUCKET_NAME, Prefix: key, MaxKeys: 10 }), { abortSignal: AbortSignal.timeout(15000) });
        if (!versions.Versions?.some(item => item.Key === key && item.VersionId === version)) throw new Error("The uploaded version was not returned by version listing");
        console.log("B2 versioned gzip upload/download and version listing: passed");
      } finally {
        if (version) {
          await client.send(new DeleteObjectCommand({ Bucket: env.B2_BUCKET_NAME, Key: key, VersionId: version }), { abortSignal: AbortSignal.timeout(15000) });
          console.log("B2 probe object version deleted");
        }
      }
    }
  } catch (error) { console.log(`B2 bucket check failed: ${error.name}. Check endpoint, bucket and application-key permissions.`); process.exitCode = 1; }
}
