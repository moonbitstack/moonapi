// The page's scroll bar keeps out of the way at the top of the page, where
// there is nothing behind it, and shows from the first scroll on. It keeps its
// place either way, so nothing shifts when it appears.
const root = document.documentElement;
const mark = () => root.classList.toggle("at-top", scrollY === 0);
addEventListener("scroll", mark, { passive: true });
mark();
