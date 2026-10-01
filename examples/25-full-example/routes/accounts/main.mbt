///|
pub fn make_router(profile_schema : @moonapi.Schema) -> @moonapi.Router {
  let router = @moonapi.Router::new()
  router.get(
    "/me",
    ctx => {
      let full_profile : Map[String, Json] = Map([
        ("id", (233).to_json()),
        ("name", ctx.cookie("display_name").unwrap_or("demo").to_json()),
        ("email", "demo@example.com".to_json()),
      ])
      let response = @moonapi.json_model(
        200,
        profile_schema,
        full_profile.to_json(),
      )
      @moonapi.set_cookie(response, "last_seen", "today", http_only=true)
    },
    summary="Return the authenticated public profile",
    security=[
      @moonapi.SecurityRequirement::new("BearerAuth", scopes=["profile:read"]),
    ],
    dependencies=["audit"],
  )
  router.post(
    "/greet",
    ctx => {
      match
        (
          ctx.body_validated(@moonapi.GreetReq::schema()) :
          Result[@moonapi.GreetReq, _]) {
        Ok(greet) =>
          @moonapi.json(200, @services.detail("Hello, " + greet.name))
        Err(errors) => @moonapi.unprocessable(errors)
      }
    },
    summary="Validate and deserialize a JSON request",
  )
  router.post(
    "/form",
    ctx => {
      match ctx.form() {
        Some(form) =>
          @moonapi.text(
            200,
            "display_name=" + form.field("display_name").unwrap_or("-"),
          )
        None => @moonapi.text(400, "invalid form")
      }
    },
    summary="Read a URL-encoded form",
  )
  router.get(
    "/download",
    _ctx => @moonapi.file_response(b"moonapi demo file", filename="guide.txt"),
    summary="Download a file response",
  )
  router
}
