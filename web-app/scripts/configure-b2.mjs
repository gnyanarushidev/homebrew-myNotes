import nextEnv from "@next/env";
import { S3Client, GetBucketCorsCommand, PutBucketCorsCommand, GetBucketAclCommand } from "@aws-sdk/client-s3";
nextEnv.loadEnvConfig(process.cwd(), false, { info() {}, error() {} });
const env = process.env;
async function main() {
  const args = process.argv.slice(2), origins = [];
  for (let i = 0; i < args.length; i++) if (args[i] === "--origin") origins.push(args[++i]);
  if (!origins.length) origins.push(env.APP_URL);
  const allowed = [...new Set(origins.map(value => {
    const url = new URL(value);
    if (url.origin !== value || (url.protocol !== "https:" && !["localhost", "127.0.0.1"].includes(url.hostname))) throw new Error("Use exact HTTPS origins or a local development origin.");
    return url.origin;
  }))];
  if (!["B2_ENDPOINT", "B2_REGION", "B2_BUCKET_NAME", "B2_APPLICATION_KEY_ID", "B2_APPLICATION_KEY"].every(key => env[key])) throw new Error("Configure the B2 server settings first.");
  const client = new S3Client({ endpoint: env.B2_ENDPOINT, region: env.B2_REGION, forcePathStyle: true, credentials: { accessKeyId: env.B2_APPLICATION_KEY_ID, secretAccessKey: env.B2_APPLICATION_KEY }, requestChecksumCalculation: "WHEN_REQUIRED" });
  const acl = await client.send(new GetBucketAclCommand({ Bucket: env.B2_BUCKET_NAME }));
  if (acl.Grants?.some(grant => grant.Grantee?.URI?.endsWith("/AllUsers"))) throw new Error("The notebook bucket must be private.");
  let rules = [];
  try { rules = (await client.send(new GetBucketCorsCommand({ Bucket: env.B2_BUCKET_NAME }))).CORSRules ?? []; }
  catch (error) { if (error.name !== "NoSuchCorsConfiguration") throw error; }
  const previous = rules.find(rule => rule.ID === "mynotes-browser");
  const rule = { ID: "mynotes-browser", AllowedOrigins: [...new Set([...(previous?.AllowedOrigins ?? []), ...allowed])], AllowedMethods: ["GET", "HEAD", "PUT"], AllowedHeaders: ["*"], ExposeHeaders: ["ETag", "x-amz-version-id"], MaxAgeSeconds: 3600 };
  console.log(`MyNotes browser origins: ${rule.AllowedOrigins.join(", ")}`);
  if (!args.includes("--apply")) { console.log("Preview only. Add --apply to configure this CORS rule."); return; }
  await client.send(new PutBucketCorsCommand({ Bucket: env.B2_BUCKET_NAME, CORSConfiguration: { CORSRules: [...rules.filter(rule => rule.ID !== "mynotes-browser"), rule] } }));
  console.log("B2 MyNotes browser CORS configured. Bucket access remains private.");
}
main().catch(error => { console.error(`B2 configuration failed: ${error.name}: ${error.message}`); process.exitCode = 1; });
