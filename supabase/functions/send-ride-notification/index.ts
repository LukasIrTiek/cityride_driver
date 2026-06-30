import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {

  const body = await req.json();

  const token = body.token;

  const title = body.title;

  const message = body.message;

  const serviceAccount =
    JSON.parse(
      Deno.env.get("FCM_SERVICE_ACCOUNT")!
    );

  const accessToken =
    await getAccessToken(serviceAccount);

  const response = await fetch(

    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,

    {

      method: "POST",

      headers: {

        Authorization:
          `Bearer ${accessToken}`,

        "Content-Type":
          "application/json",
      },

      body: JSON.stringify({

        message: {

          token: token,

          notification: {

            title: title,

            body: message,
          },

          android: {

            priority: "high",

            notification: {

              channel_id: "high_importance_channel",

              sound: "default",

              default_sound: true,

              default_vibrate_timings: true,
            },
          },
        },
      }),
    }
  );

  const data =
    await response.text();

  return new Response(data);
});

async function getAccessToken(
  serviceAccount: any
) {

  const jwt =
    await createJWT(serviceAccount);

  const response = await fetch(

    "https://oauth2.googleapis.com/token",

    {

      method: "POST",

      headers: {

        "Content-Type":
          "application/x-www-form-urlencoded",
      },

      body:
        `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    }
  );

  const data =
    await response.json();

  return data.access_token;
}

async function createJWT(
  serviceAccount: any
) {

  const header = {

    alg: "RS256",

    typ: "JWT",
  };

  const now =
    Math.floor(Date.now() / 1000);

  const payload = {

    iss: serviceAccount.client_email,

    scope:
      "https://www.googleapis.com/auth/firebase.messaging",

    aud:
      "https://oauth2.googleapis.com/token",

    exp: now + 3600,

    iat: now,
  };

  const encoder =
    new TextEncoder();

  const headerBase64 =
    btoa(JSON.stringify(header));

  const payloadBase64 =
    btoa(JSON.stringify(payload));

  const data =
    `${headerBase64}.${payloadBase64}`;

  const key =
    await crypto.subtle.importKey(

      "pkcs8",

      pemToArrayBuffer(
        serviceAccount.private_key
      ),

      {

        name: "RSASSA-PKCS1-v1_5",

        hash: "SHA-256",
      },

      false,

      ["sign"]
    );

  const signature =
    await crypto.subtle.sign(

      "RSASSA-PKCS1-v1_5",

      key,

      encoder.encode(data)
    );

  const signatureBase64 =
    btoa(
      String.fromCharCode(
        ...new Uint8Array(signature)
      )
    );

  return `${data}.${signatureBase64}`;
}

function pemToArrayBuffer(
  pem: string
) {

  const base64 =
    pem
      .replace(
        /-----BEGIN PRIVATE KEY-----/,
        ""
      )
      .replace(
        /-----END PRIVATE KEY-----/,
        ""
      )
      .replace(/\n/g, "");

  const binary =
    atob(base64);

  const bytes =
    new Uint8Array(binary.length);

  for (
    let i = 0;
    i < binary.length;
    i++
  ) {

    bytes[i] =
      binary.charCodeAt(i);
  }

  return bytes.buffer;
}