import { ActionLink, EmptyState, PublicHeader } from "@/components/ui/ui";

export default function NotFound() {
  return <><PublicHeader /><main id="main-content" style={{ maxWidth: 650, margin: "70px auto", padding: "0 20px" }}><EmptyState title="This page is still a blank canvas."><p>We couldn’t find the page you were looking for. Let’s get you back to your workspace.</p><ActionLink href="/notebooks">Back to notebook preview</ActionLink></EmptyState></main></>;
}
