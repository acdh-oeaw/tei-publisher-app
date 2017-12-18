<code-editor>
    <pre ref="code" onclick="{ initCodeEditor }" class="{ mode }">{ this.code }</pre>

    <script>
    this.mixin('utils');
    var self = this;

    this.code = opts.code;
    this.mode = opts.mode;
    this.placeholder = opts.placeholder;
    this.callback = opts.callback;

    this.app.on('show', function() {
        self.initCodeEditor();
    });

    this.on('mount', function() {
        self.initCodeEditor();
    });

    initCodeEditor() {
        if (this.codemirror || !$(this.refs.code).is(":visible")) {
            return;
        }
        this.codemirror = CodeMirror(function(elt) {
            self.refs.code.style.display = 'none';
            self.refs.code.parentNode.appendChild(elt);
        }, {
            value: self.code,
            mode: self.mode,
            lineNumbers: false,
            lineWrapping: true,
            autofocus: false,
            theme: "ttcn",
            matchBrackets: true,
            placeholder: self.placeholder || '[Empty]',
            gutters: ["CodeMirror-lint-markers"],
            lint: true
        });
        if (this.callback) {
            this.codemirror.on('change', this.callback);
        }
    }

    get() {
        if (this.codemirror) {
            return this.codemirror.getValue();
        }
        return this.code;
    }
    </script>
</code-editor>