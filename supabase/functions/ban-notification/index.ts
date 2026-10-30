import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SITE_URL = Deno.env.get("SITE_URL") || "https://chain-revival-ax0q1g.fly.dev";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload = await req.json();
    const record = payload.record;

    if (!record?.is_banned || payload.type !== "UPDATE") {
      return new Response(JSON.stringify({ skipped: true }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: user } = await supabase.auth.admin.getUserById(record.id);
    if (!user?.user?.email) {
      return new Response(JSON.stringify({ error: "No email found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    const appealUrl = `${SITE_URL}/appeal?id=${record.id}`;
    const banReason = record.ban_reason || "Violation of community guidelines";

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Chain Revival <noreply@chain-revival.com>",
        to: user.user.email,
        subject: "Chain Revival — Account Banned",
        html: `
          <div style="font-family: system-ui, sans-serif; max-width: 560px; margin: 0 auto; padding: 32px; background: #0f172a; color: #e2e8f0; border-radius: 12px;">
            <h1 style="color: #f8fafc; font-size: 24px; margin-bottom: 16px;">Account Banned</h1>
            <p>Your Chain Revival account <strong>${record.display_name}</strong> has been banned.</p>
            <p><strong>Reason:</strong> ${banReason}</p>
            <p>If you believe this was a mistake, you can submit a ban appeal:</p>
            <a href="${appealUrl}" style="display: inline-block; margin-top: 12px; padding: 10px 24px; background: #0284c7; color: white; text-decoration: none; border-radius: 8px; font-weight: 600;">Submit Appeal</a>
            <p style="margin-top: 24px; color: #94a3b8; font-size: 13px;">— Chain Revival Team</p>
          </div>
        `,
      }),
    });

    const emailData = await emailRes.json();

    return new Response(JSON.stringify({ sent: true, emailData }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
