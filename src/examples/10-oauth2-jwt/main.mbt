///|
/// The OAuth2 password-bearer flow end to end. A `/token` endpoint reads an
/// `OAuth2PasswordRequestForm` off the urlencoded body, checks the credentials,
/// and issues an HS256 JWT with `create_access_token`, replying through
/// `token_response`. A protected route hands its context to
/// `OAuth2PasswordBearer::authenticate`, which pulls the `Authorization: Bearer`
/// header, verifies the token at a fixed clock, and enforces scopes: `401`
/// unauthenticated, `403` when a scope is missing, the `AuthenticatedUser`
/// otherwise. Times are Unix seconds, passed in so the checks are deterministic.
///
///     moon run src/examples/10-oauth2-jwt
#coverage.skip
async fn main {
  let secret = "heke1228-signing-secret"
  let bearer = @moonapi.OAuth2PasswordBearer::new("/token", secret)
  let now = 1_700_000_000L
  let app = @moonapi.App::new()
  app.post("/token", ctx => {
    match ctx.oauth2_password_form() {
      Some(form) =>
        if form.username == "lfanke" && form.password == "qwq" {
          let tok = @moonapi.create_access_token(
            form.username,
            secret,
            now,
            scopes=form.scopes,
          )
          @moonapi.token_response(tok)
        } else {
          @moonapi.text(401, "bad credentials")
        }
      None => @moonapi.text(400, "not a password form")
    }
  })
  app.get("/items", ctx => {
    match bearer.authenticate(ctx, now, scopes=["items:read"]) {
      Ok(user) =>
        @moonapi.text(
          200,
          "items for \{user.subject}, scopes=[\{join_csv(user.scopes)}], read=\{user.has_scope("items:read")}",
        )
      Err(resp) => resp
    }
  })

  // 1. Exchange credentials at the token endpoint (urlencoded, `+` = space).
  let token_req : @moonasgi.Request = {
    http_method: "POST",
    path: "/token",
    query_string: b"",
    headers: [("content-type", "application/x-www-form-urlencoded")],
    body: @utf8.encode(
      "grant_type=password&username=lfanke&password=qwq&scope=items:read+profile",
    ),
  }
  let token_resp = app.handle(token_req)
  println(
    "POST /token -> \{token_resp.status} \{@utf8.decode_lossy(token_resp.body[:])}",
  )

  // A token carrying the required scope, and one without it.
  let good = @moonapi.create_access_token("lfanke", secret, now, scopes=[
    "items:read", "profile",
  ])
  let weak = @moonapi.create_access_token("lfanke", secret, now, scopes=[
    "profile",
  ])
  let get_items = (label : String, headers : Array[(String, String)]) => {
    let req : @moonasgi.Request = {
      http_method: "GET",
      path: "/items",
      query_string: b"",
      headers,
      body: b"",
    }
    let r = app.handle(req)
    println(
      "GET /items \{label} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}",
    )
  }
  // 2. No Authorization header -> 401.
  get_items("(no token)", [])
  // 3. A token with the scope -> 200.
  get_items("(items:read)", [("authorization", "Bearer " + good)])
  // 4. A valid token missing the scope -> 403.
  get_items("(profile only)", [("authorization", "Bearer " + weak)])

  // bearer_token pulls the raw credential straight off the header.
  let probe : @moonapi.Context = @moonapi.Context::new(
    {
      http_method: "GET",
      path: "/items",
      query_string: b"",
      headers: [("authorization", "Bearer " + good)],
      body: b"",
    },
    params=Map([]),
  )
  println("bearer_token present: \{probe.bearer_token() is Some(_)}")
}

///|
/// Join strings with commas — collections render through `Debug`, not string
/// interpolation, so an example spells the formatting out.
fn join_csv(xs : Array[String]) -> String {
  let sb = StringBuilder()
  for i = 0; i < xs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(xs[i])
  }
  sb.to_string()
}
