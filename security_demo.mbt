// A worked OAuth2 password-bearer app — FastAPI's security tutorial in explicit
// MoonBit form. `POST /token` reads the password form, checks the demo
// credentials, and issues a scoped HS256 JWT; `GET /users/me` is protected by a
// bearer `Security` with no scope requirement; `GET /users/me/items` additionally
// requires the `items` scope. The verification clock is injected (`now`) so the
// same app runs deterministically in a test and against the wall clock in
// production.

///|
/// Check the demo credentials. A real app would look the user up and verify a
/// password hash; here one hard-coded account keeps the example self-contained.
fn authenticate_user(username : String, password : String) -> Bool {
  username == "alice" && password == "wonderland"
}

///|
/// Build the OAuth2 demo application. `secret` is the shared HS256 key; `now`
/// supplies the current Unix time (seconds) for both issuing and verifying, so a
/// caller controls time in tests. Tokens live for one hour.
pub fn oauth2_app(now : () -> Int64, secret~ : String = "demo-secret") -> App {
  let app = App::new()
  let scheme = OAuth2PasswordBearer::new("/token", secret)
  app.post(
    "/token",
    ctx => {
      match ctx.oauth2_password_form() {
        None => unprocessable([ValidationError::missing(["body", "username"])])
        Some(form) =>
          if authenticate_user(form.username, form.password) {
            let token = create_access_token(
              form.username,
              secret,
              now(),
              scopes=form.scopes,
            )
            token_response(token)
          } else {
            let body : Map[String, Json] = Map([
              ("detail", Json("Incorrect username or password")),
            ])
            @moonasgi.Response::new(
              401,
              [
                ("content-type", "application/json"),
                ("www-authenticate", "Bearer"),
              ],
              @moonjson.dump(Json(body)),
            )
          }
      }
    },
    summary="issue an access token",
  )
  app.get(
    "/users/me",
    ctx => {
      match scheme.authenticate(ctx, now()) {
        Err(resp) => resp
        Ok(user) => {
          let scopes : Array[Json] = []
          for s in user.scopes {
            scopes.push(Json(s))
          }
          let body : Map[String, Json] = Map([
            ("username", Json(user.subject)),
            ("scopes", Json(scopes)),
          ])
          json(200, Json(body))
        }
      }
    },
    summary="the current user",
  )
  app.get(
    "/users/me/items",
    ctx => {
      match scheme.authenticate(ctx, now(), scopes=["items"]) {
        Err(resp) => resp
        Ok(user) => {
          let body : Map[String, Json] = Map([
            ("owner", Json(user.subject)),
            ("items", Json(["hammer", "nail"])),
          ])
          json(200, Json(body))
        }
      }
    },
    summary="the current user's items (scope: items)",
  )
  app
}
