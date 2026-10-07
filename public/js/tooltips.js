(function () {
  'use strict';

  var options = { container: 'body', trigger: 'hover focus' };

  document.querySelectorAll('[data-tooltip]').forEach(function (element) {
    new bootstrap.Tooltip(element, options);
    element.addEventListener('click', function () {
      bootstrap.Tooltip.getInstance(element).hide();
    });
  });

  window.addFavorite = function (element) {
    var favorite = element.dataset.favorite !== 'true';
    return fetch('/favorite/' + element.value, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'favorite=' + favorite
    }).then(function (response) {
      if (!response.ok) return;
      var label = favorite ? 'Remove from favorites' : 'Add to favorites';
      element.dataset.favorite = String(favorite);
      element.setAttribute('aria-label', label);
      element.classList.remove('bi-star', 'bi-star-fill', 'bi-bookmark-star');
      element.classList.add(favorite ? 'bi-star-fill' : 'bi-star');
      element.setAttribute('data-bs-original-title', label);
      bootstrap.Tooltip.getInstance(element).setContent({ '.tooltip-inner': label });
      bootstrap.Tooltip.getInstance(element).hide();
    });
  };

  window.recreateThumb = function (element) {
    return fetch('/thumb/recreate/' + element.value, { method: 'POST' });
  };
})();
