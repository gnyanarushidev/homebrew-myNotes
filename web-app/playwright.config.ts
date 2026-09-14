import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*.spec.ts",
  // The local provider is stateful; reset/account changes must not overlap.
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: "list",
  use: {
    ...devices["Desktop Chrome"],
    baseURL: "http://127.0.0.1:3101",
    viewport: { width: 1440, height: 1000 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  webServer: [{
    command: "node tests/support/mock-supabase.mjs",
    url: "http://127.0.0.1:54329/auth/v1/settings",
    reuseExistingServer: false,
  }, {
    command: "npm run start",
    url: "http://127.0.0.1:3101/api/v1/health",
    reuseExistingServer: false,
    env: {
      PORT: "3101",
      NEXT_TELEMETRY_DISABLED: "1",
      APP_URL: "http://127.0.0.1:3101",
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54329",
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
      SUPABASE_SECRET_KEY: "sb_secret_test",
      ADMIN_EMAIL: "admin@example.com",
      B2_ENDPOINT: "http://127.0.0.1:54329",
      B2_REGION: "us-west-004",
      B2_BUCKET_NAME: "test-bucket",
      B2_APPLICATION_KEY_ID: "test-access",
      B2_APPLICATION_KEY: "test-secret",
    },
    timeout: 30_000,
  }],
});
