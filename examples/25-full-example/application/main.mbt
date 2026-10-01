///|
pub fn build() -> @moonapi.App {
  let audit_log : Array[String] = []
  let app = @moonapi.App::new()
  app.describe(
    title="MoonAPI Full Example",
    api_version="1.0.0",
    description="A layered application composed from two routers.",
  )
  app.set_clock(() => @async.now() / 1000L)
  app.middleware(
    @moonapi.cors(
      allow_origins=["https://client.example.com"],
      allow_credentials=true,
    ),
  )
  app.middleware(@moonapi.gzip(min_size=32))
  app.add_status_handler(404, _ctx => {
    @moonapi.json(404, @services.detail("not found"))
  })
  app.exception_handler((_ctx, err) => {
    match err {
      DemoError::Rejected(reason) =>
        Some(@moonapi.json(409, @services.detail(reason)))
      _ => None
    }
  })
  app.on_startup(() => audit_log.push("startup"))
  app.on_shutdown(() => audit_log.push("shutdown"))
  app.enable_docs(version=@moonapi.OpenApi30)

  let deps = @services.dependencies(audit_log)
  app.depends(deps.erase())

  let secret = "demo-only-signing-key"
  let bearer = @moonapi.OAuth2PasswordBearer::new("/token", secret)
  app.secure_oauth2("BearerAuth", bearer, scopes=[
    ("profile:read", "Read the current profile"),
  ])
  app.get("/", _ctx => @moonapi.text(200, "moonapi full example"))
  app.get("/health", _ctx => @moonapi.json(200, @services.detail("ok")))
  app.post("/token", ctx => {
    match ctx.oauth2_password_form() {
      Some(form) if form.username == "demo" && form.password == "demo" => {
        let now = @async.now() / 1000L
        let token = @moonapi.create_access_token(form.username, secret, now, scopes=[
          "profile:read",
        ])
        @moonapi.token_response(token)
      }
      Some(_) => @moonapi.text(401, "invalid credentials")
      None => @moonapi.text(400, "expected a password grant form")
    }
  })
  app.get("/reject", _ctx => raise DemoError::Rejected("example conflict"))

  let profile_schema = @moonapi.Schema::object("PublicProfile", [
    @moonapi.Field::new("id", @moonapi.SInt),
    @moonapi.Field::new("name", @moonapi.SStr),
  ])
  app.include_router(
    @accounts.make_router(profile_schema),
    prefix="/api/v1/accounts",
    tags=["accounts"],
  )
  app.include_router(
    @catalog.make_router(audit_log),
    prefix="/api/v1/catalog",
    tags=["catalog"],
  )
  app
}

///|
priv suberror DemoError {
  Rejected(String)
}
