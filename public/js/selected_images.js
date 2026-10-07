(function () {
  'use strict';

  [['ImagesMoveModal', 'mv_md5s'], ['ImagesDeleteModal', 'del_md5s']].forEach(function (entry) {
    var modal = document.getElementById(entry[0]);
    if (!modal) return;
    modal.addEventListener('show.bs.modal', function () {
      var selectedImages = Array.from(document.querySelectorAll('.image_checkbox:checked'), function (checkbox) {
        return checkbox.value;
      });
      document.getElementById(entry[1]).value = selectedImages.join(',');
    });
  });
})();
