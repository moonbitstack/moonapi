/* The request-path figure is a drawing, not a widget: what it needs from a script
   is a way back to the character drawing beside it if the file cannot be read —
   an archive without images, a broken copy, a network that eats the request. */
const img = document.querySelector(".arch-img");
if (img) {
  const fallback = () => img.closest(".arch").classList.add("no-img");
  if (img.complete && img.naturalWidth === 0) fallback();
  img.addEventListener("error", fallback);
}
