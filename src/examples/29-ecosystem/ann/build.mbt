///|
/// The application, built from what the annotations generate.
pub fn build() -> @moonapi.App {
  let app = @moonapi.App::new()
  @shared.configure(app)
  register(app)
  app
}
