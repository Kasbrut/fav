const header = document.querySelector('.site-header');
const toggle = document.querySelector('.nav-toggle');
const nav = document.querySelector('#site-nav');

if (header && toggle && nav) {
  const mobile = window.matchMedia('(max-width: 760px)');
  const setOpen = (open) => {
    nav.hidden = mobile.matches && !open;
    toggle.setAttribute('aria-expanded', String(open));
  };

  header.classList.add('nav-ready');
  toggle.hidden = false;
  setOpen(false);
  toggle.addEventListener('click', () => setOpen(toggle.getAttribute('aria-expanded') !== 'true'));
  nav.addEventListener('click', (event) => {
    if (event.target.closest('a') && mobile.matches) setOpen(false);
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') {
      setOpen(false);
      toggle.focus();
    }
  });
  mobile.addEventListener('change', () => setOpen(false));
}
