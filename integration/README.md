# moonapi-ecosystem

One description of a task, in `moonmodel`'s vocabulary, projected into the request
body the API validates, the document it publishes and the SQLite table it stores rows
in: the rows written through the ORM, an API key on the writes, CORS and gzip around
the router, and an error page for anything uncaught. The routes are registered three
ways (`ann`, `fns`, `cls`), and `check` fails when the three do not answer alike.

It is a module of its own because a program that uses `moonapi` should not download
an ORM and a vendored SQLite for the sake of an example.

```bash
moon run integration/src --target native
moon run integration/src/check --target native
```

`full-example` is one service with every feature composed, served by mooncat on `http://127.0.0.1:12000`:

```bash
moon run integration/src/full-example --target native
```
