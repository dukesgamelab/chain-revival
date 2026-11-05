// Ban notification emails disabled until an official domain is purchased and
// verified in Resend. The previous implementation sent from chain-revival.com
// which is not owned by this project.
//
// To re-enable: buy a domain, verify it in Resend, set RESEND_API_KEY and
// SITE_URL env vars, and restore the email sending logic.

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  return new Response(JSON.stringify({ skipped: true, reason: "email disabled" }), {
    headers: { "Content-Type": "application/json" },
  });
});
