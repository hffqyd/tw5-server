function create_li(f) {
  var li = document.createElement('li');
  li.setAttribute('class', 'i-file entypo');
  li.innerHTML = '<a href="' + f + '">' + f + '</a>';
  return li;
}

function add_to_ul(f) {
  var ul = document.querySelector('ul');
  var li = create_li(f);
  if (ul.children[0].innerText == '..') {
    ul.insertBefore(li, ul.children[1]); // first is the back link if in sub-dir
  } else {
    ul.insertBefore(li, ul.children[0]);
  }
}

function notify(note) {
  var nojump = document.querySelector('#nojump');
  nojump.innerHTML = note;
}

function post_file(file) {
  var formdata  = new FormData();
  formdata.append("file", file, file.name);
  var override = document.querySelector('#override_check');
  if (override.checked) {
    formdata.append('override', 'yes');
  }
  // request
  var xhr = new XMLHttpRequest();
  xhr.open("POST", '', true);
  xhr.onreadystatechange = function () {
    if (xhr.readyState != 4 || xhr.status != 200) {
      notify('Error: ' + xhr.responseText);
    } else {
      notify('Saved to ' + xhr.responseText);
      add_to_ul(xhr.responseText);
    }
}
  //var boundary = '-------------------' + Date.now().toString(16);
  //xhr.setRequestHeader('Content-Type', 'multipart\/form-data; boundary=' + boundary);
  xhr.send(formdata);
}

var submit = document.querySelector('label[type="submit"]');
submit.addEventListener('click', function(event) {
  event.preventDefault();

  var input = document.querySelector('input[type="file"]');
  if (input.files.length < 1) {return;}
  const file = input.files[0];

  post_file(file);
})

// drag to upload
var target = document.querySelector('body');
var changed_color = '#dcf8c6'; //'#BEDDAA'
var original_color = target.getAttribute('background-color');
if (original_color == null) {
  original_color = '';
}

target.addEventListener('drop', function(event) {
  event.preventDefault();
  if (event.type === 'drop') {
    var file = event.dataTransfer.files[0];
    post_file(file)
  }
  target.style.backgroundColor = original_color;
})

target.addEventListener('dragenter', function (event) {
    event.preventDefault();
    target.style.backgroundColor = changed_color;
})
target.addEventListener('dragover', function (event) {
    event.preventDefault();
    target.style.backgroundColor = changed_color;
})
target.addEventListener('dragleave', function (event) {
    event.preventDefault();
    target.style.backgroundColor = original_color;
})

