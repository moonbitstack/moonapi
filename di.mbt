// A dependency-injection container — the explicit, MoonBit-idiomatic equivalent
// of FastAPI's `Depends`. FastAPI reads a dependency's callable off the handler
// signature and resolves it per request, caching the result and running any
// `yield` teardown afterwards. MoonBit has no runtime reflection and no `Any`,
// so the container is a first-class value keyed by name, and its dependency
// value type `V` is an explicit parameter: for a single dependency type `V` is
// that type; for several, `V` is a user-defined sum type wrapping them — the
// exhaustive, type-safe stand-in for Python's dynamic `Any` (cf. axum's typemap
// + downcast, Go's `interface{}` + type assertion). Everything else — the
// registry, request-scoped one-shot resolution, sub-dependencies (a factory
// resolving others through the scope, with cycle detection), `yield`-style
// teardown, and `dependency_overrides` — is modelled faithfully.

///|
/// A provider: a keyed factory that builds a request-scoped dependency value,
/// with an optional teardown run after the handler (FastAPI's `yield`
/// dependencies, whose post-`yield` body is cleanup). The `factory` runs at most
/// once per request scope; the `teardown` receives the produced value and the
/// error that ended the request, `None` when it succeeded — the exception a
/// FastAPI `yield` dependency sees when it wraps its `yield` in a `try`. The
/// factory is handed the `Scope` so it can resolve *sub-dependencies* through it
/// — FastAPI's `Depends(a)` where `a` itself declares `Depends(b)`.
pub(all) struct Provider[V] {
  factory : (Scope[V]) -> V
  teardown : (V, Error?) -> Unit
}

///|
/// Build a leaf provider whose factory needs nothing else. `teardown` defaults to
/// a no-op — the common "plain value, nothing to release" case.
pub fn[V] Provider::new(
  factory : () -> V,
  teardown~ : (V, Error?) -> Unit = (_v, _e) => (),
) -> Provider[V] {
  { factory: _scope => factory(), teardown, }
}

///|
/// Build a provider whose factory resolves other dependencies through the request
/// `Scope` it is handed — the sub-dependency case (FastAPI's nested `Depends`).
pub fn[V] Provider::scoped(
  factory : (Scope[V]) -> V,
  teardown~ : (V, Error?) -> Unit = (_v, _e) => (),
) -> Provider[V] {
  { factory, teardown, }
}

///|
/// The provider registry: `key -> Provider`, plus a separate `overrides` map
/// that shadows it. Overrides are FastAPI's `app.dependency_overrides` — a test
/// swaps a real dependency (a live DB session) for a fake without touching the
/// routes. A registered override always wins over the base provider.
pub(all) struct Container[V] {
  providers : Map[String, Provider[V]]
  overrides : Map[String, Provider[V]]
}

///|
/// An empty container.
pub fn[V] Container::new() -> Container[V] {
  { providers: Map([]), overrides: Map([]), }
}

///|
/// Register a base provider under `key` (last registration wins), returning the
/// container so registrations can chain.
pub fn[V] Container::provide(
  self : Container[V],
  key : String,
  factory : () -> V,
  teardown~ : (V, Error?) -> Unit = (_v, _e) => (),
) -> Container[V] {
  self.providers[key] = Provider::new(factory, teardown~)
  self
}

///|
/// Register a base provider whose factory resolves sub-dependencies through the
/// request scope it is handed (FastAPI's nested `Depends`). Otherwise like
/// `provide`.
pub fn[V] Container::provide_using(
  self : Container[V],
  key : String,
  factory : (Scope[V]) -> V,
  teardown~ : (V, Error?) -> Unit = (_v, _e) => (),
) -> Container[V] {
  self.providers[key] = Provider::scoped(factory, teardown~)
  self
}

///|
/// Register a dependency override for `key` — FastAPI's
/// `app.dependency_overrides[dep] = fake`. Takes precedence over the base
/// provider until cleared.
pub fn[V] Container::override_(
  self : Container[V],
  key : String,
  factory : () -> V,
  teardown~ : (V, Error?) -> Unit = (_v, _e) => (),
) -> Container[V] {
  self.overrides[key] = Provider::new(factory, teardown~)
  self
}

///|
/// Drop the override for `key` (no-op if none), restoring the base provider.
pub fn[V] Container::clear_override(self : Container[V], key : String) -> Unit {
  self.overrides.remove(key)
}

///|
/// Drop every override — the usual test teardown that returns the container to
/// its production wiring.
pub fn[V] Container::clear_overrides(self : Container[V]) -> Unit {
  self.overrides.clear()
}

///|
/// The effective provider for `key`: an override if one is registered, else the
/// base provider, else `None`.
fn[V] Container::resolve(self : Container[V], key : String) -> Provider[V]? {
  match self.overrides.get(key) {
    Some(p) => Some(p)
    None => self.providers.get(key)
  }
}

///|
/// A request-scoped resolution scope. Each dependency is built at most once and
/// its value cached for the life of the scope (FastAPI's per-request dependency
/// cache), and each built value's teardown is recorded to run — in reverse
/// registration order (LIFO) — when the scope closes. Open one per request,
/// resolve dependencies through it, then `close` it (or use `Container::run`).
pub struct Scope[V] {
  container : Container[V]
  cache : Map[String, V]
  building : Map[String, Bool]
  teardowns : Array[(Error?) -> Unit]
}

///|
/// Open a fresh request scope over this container.
pub fn[V] Container::open_scope(self : Container[V]) -> Scope[V] {
  { container: self, cache: Map([]), building: Map([]), teardowns: [], }
}

///|
/// Resolve `key` within this scope: return the already-built instance if the
/// dependency was resolved earlier in the same request; otherwise run its
/// factory once, cache the value, register its teardown, and return it. `None`
/// when no provider (or override) is registered for `key`.
pub fn[V] Scope::get(self : Scope[V], key : String) -> V? {
  match self.cache.get(key) {
    Some(v) => Some(v)
    None => {
      // A key already mid-build has been re-entered: a circular dependency.
      // Break it with `None` rather than looping (FastAPI raises here).
      if self.building.get(key) is Some(_) {
        return None
      }
      match self.container.resolve(key) {
        None => None
        Some(prov) => {
          self.building[key] = true
          let v = (prov.factory)(self)
          self.building.remove(key)
          self.cache[key] = v
          let td = prov.teardown
          self.teardowns.push(failure => td(v, failure))
          Some(v)
        }
      }
    }
  }
}

///|
/// Run every recorded teardown in LIFO order and clear them, so a closed scope
/// is inert. Mirrors FastAPI unwinding `yield` dependencies in reverse — the
/// last opened is torn down first. `failure` is the error that ended the request
/// and is handed to every teardown, so cleanup can tell a failed request from a
/// successful one and roll back rather than commit.
pub fn[V] Scope::close(self : Scope[V], failure? : Error) -> Unit {
  for i = self.teardowns.length() - 1; i >= 0; i = i - 1 {
    self.teardowns[i](failure)
  }
  self.teardowns.clear()
}

///|
/// Run `handler` inside a fresh request scope, then tear the scope down — the
/// setup/teardown pair wrapped around a handler, exactly as a FastAPI `yield`
/// dependency brackets the request. The handler resolves whatever it needs
/// through the scope; every dependency built during the call is released
/// (LIFO) once it returns, then the response is handed back.
///
/// A handler that raises is released the same way, and the error reaches the
/// teardowns before it is re-raised for the app's exception handlers to map:
/// cleanup that only ran on the happy path would leak exactly when it matters.
pub fn[V] Container::run(
  self : Container[V],
  handler : (Scope[V]) -> @moonasgi.Response raise,
) -> @moonasgi.Response raise {
  let scope = self.open_scope()
  // `errdefer` cannot bind the error, and the teardowns are entitled to see it,
  // so the outcome is captured and dispatched on instead.
  let outcome : Result[@moonasgi.Response, Error] = Ok(handler(scope)) catch {
    err => Err(err)
  }
  match outcome {
    Ok(resp) => {
      scope.close()
      resp
    }
    Err(err) => {
      scope.close(failure=err)
      raise err
    }
  }
}

///|
/// A container with its dependency value type erased (`Container::erase` builds
/// one), so a non-generic `App` can hold one. Resolving through it runs a
/// provider's factory and records its teardown exactly as `Scope::get` does;
/// what it cannot do is hand the value back — which is precisely what a
/// route-level dependency does not need, since FastAPI's `dependencies=[...]`
/// discards the values it builds and keeps only their effects.
pub struct Deps {
  open : () -> DepsScope
}

///|
/// One request's resolution scope over an erased container: resolve a key
/// (`false` when nothing provides it), then close, handing any failure to the
/// teardowns.
struct DepsScope {
  resolve : (String) -> Bool
  close : (Error?) -> Unit
}

///|
/// This container with its value type erased, ready for `App::depends`. The
/// providers, the per-request cache, the sub-dependency resolution and the LIFO
/// teardown are all the container's own; erasure hides only the value.
pub fn[V] Container::erase(self : Container[V]) -> Deps {
  {
    open: () => {
      let scope = self.open_scope()
      {
        resolve: key => scope.get(key) is Some(_),
        close: failure => scope.close(failure?),
      }
    },
  }
}
