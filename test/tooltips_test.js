'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

test("Bootstrap 5: initialize, hide and update favorite tooltip", async () => {
    const attributes = {};
    const calls = [];
    const element = {
      value: 'media-id', dataset: { favorite: 'false' },
      classList: { remove() {}, add(value) { calls.push(value); } },
      setAttribute(key, value) { attributes[key] = value; },
      addEventListener(event, callback) { this[event] = callback; }
    };
    const instance = { hide() { calls.push('hide'); }, setContent(value) { calls.push(value); } };
    function Tooltip(target, options) {
      assert.equal(target, element);
      assert.equal(options.trigger, 'hover focus');
      calls.push('initialized');
    }
    Tooltip.getInstance = () => instance;
    let success = false;
    const context = {
      bootstrap: { Tooltip }, document: { querySelectorAll: () => [element] }, window: {},
      fetch: async (url, options) => {
        assert.equal(url, '/favorite/media-id');
        assert.equal(options.method, 'POST');
        assert.equal(options.body, 'favorite=true');
        return { ok: success };
      }
    };
    vm.runInNewContext(fs.readFileSync('public/js/tooltips.js', 'utf8'), context);
    assert.ok(calls.includes('initialized'));
    element.click();
    assert.ok(calls.includes('hide'));
    await context.window.addFavorite(element);
    assert.equal(element.dataset.favorite, 'false');
    success = true;
    await context.window.addFavorite(element);
    assert.equal(element.dataset.favorite, 'true');
    assert.equal(attributes['aria-label'], 'Remove from favorites');
    assert.equal(attributes['data-bs-original-title'], 'Remove from favorites');
    assert.ok(calls.includes('bi-star-fill'));
  });
