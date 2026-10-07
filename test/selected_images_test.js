'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

test('batch modals read the current selection when opened', () => {
  const handlers = {};
  const fields = { mv_md5s: {}, del_md5s: {} };
  let selected = [{ value: 'first' }, { value: 'second' }];
  const document = {
    getElementById(id) {
      return fields[id] || { addEventListener(event, callback) {
        assert.equal(event, 'show.bs.modal');
        handlers[id] = callback;
      } };
    },
    querySelectorAll(selector) {
      assert.equal(selector, '.image_checkbox:checked');
      return selected;
    }
  };
  vm.runInNewContext(fs.readFileSync('public/js/selected_images.js', 'utf8'), { document });
  handlers.ImagesMoveModal();
  assert.equal(fields.mv_md5s.value, 'first,second');
  selected = [{ value: 'second' }];
  handlers.ImagesDeleteModal();
  assert.equal(fields.del_md5s.value, 'second');
  selected = [];
  handlers.ImagesMoveModal();
  assert.equal(fields.mv_md5s.value, '');
});

test('pages without batch modals initialize safely', () => {
  vm.runInNewContext(fs.readFileSync('public/js/selected_images.js', 'utf8'), {
    document: { getElementById: () => null }
  });
});
