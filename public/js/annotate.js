$(function ($) {
  var valid = /^[cfgst]$/i;

  $('#text').keydown(function (e) {
    var key = String.fromCharCode(e.keyCode).toLowerCase();
    if (!e.altKey || !e.shiftKey || !key.match(valid)) {
      return;
    }

    var text  = document.getElementById('text');
    var start = text.selectionStart;
    var end   = text.selectionEnd;
    if (start === void 0 || end === void 0) {
      return;
    }

    console.log(text.value.substring(start, end));
    var before = text.value.substring(0, start);
    var match  = text.value.substring(start, end);
    var after  = text.value.substring(end);
    var author = $('#author').val();

    var value = before + '[' + match + '](' + key;
    if (author) {
      value += '@' + author;
    }

    value += '|)';
    var pos = value.length - 1;
    value += after;

    text.value          = value;
    text.selectionStart = pos;
    text.selectionEnd   = pos;

    return false;
  });
});
