TokenizedBuffer = require '../src/tokenized-buffer'
{Point} = TextBuffer = require 'text-buffer'
_ = require 'underscore-plus'

describe "TokenizedBuffer", ->
  [tokenizedBuffer, buffer, changeHandler] = []

  beforeEach ->
    # enable async tokenization
    TokenizedBuffer.prototype.chunkSize = 5
    jasmine.unspy(TokenizedBuffer.prototype, 'tokenizeInBackground')

    waitsForPromise ->
      atom.packages.activatePackage('language-javascript')

  afterEach ->
    tokenizedBuffer?.destroy()

  startTokenizing = (tokenizedBuffer) ->
    tokenizedBuffer.setVisible(true)

  fullyTokenize = (tokenizedBuffer) ->
    tokenizedBuffer.setVisible(true)
    advanceClock() while tokenizedBuffer.firstInvalidRow()?
    changeHandler?.reset()

  describe "serialization", ->
    describe "when the underlying buffer has a path", ->
      beforeEach ->
        buffer = atom.project.bufferForPathSync('sample.js')

        waitsForPromise ->
          atom.packages.activatePackage('language-coffee-script')

      it "deserializes it searching among the buffers in the current project", ->
        tokenizedBufferA = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        tokenizedBufferB = TokenizedBuffer.deserialize(
          JSON.parse(JSON.stringify(tokenizedBufferA.serialize())),
          atom
        )

        expect(tokenizedBufferB.buffer).toBe(tokenizedBufferA.buffer)

      it "does not serialize / deserialize the current grammar", ->
        tokenizedBufferA = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        autoSelectedGrammar = tokenizedBufferA.grammar

        tokenizedBufferA.setGrammar(atom.grammars.grammarForScopeName('source.coffee'))
        tokenizedBufferB = TokenizedBuffer.deserialize(
          JSON.parse(JSON.stringify(tokenizedBufferA.serialize())),
          atom
        )

        expect(tokenizedBufferB.grammar).toBe(atom.grammars.grammarForScopeName('source.js'))

    describe "when the underlying buffer has no path", ->
      beforeEach ->
        buffer = atom.project.bufferForPathSync(null)

      it "deserializes it searching among the buffers in the current project", ->
        tokenizedBufferA = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        tokenizedBufferB = TokenizedBuffer.deserialize(
          JSON.parse(JSON.stringify(tokenizedBufferA.serialize())),
          atom
        )

        expect(tokenizedBufferB.buffer).toBe(tokenizedBufferA.buffer)

      it "deserializes the previously selected grammar as soon as it's added when not available in the grammar registry", ->
        tokenizedBufferA = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })

        tokenizedBufferA.setGrammar(atom.grammars.grammarForScopeName("source.js"))
        atom.grammars.removeGrammarForScopeName(tokenizedBufferA.grammar.scopeName)
        tokenizedBufferB = TokenizedBuffer.deserialize(
          JSON.parse(JSON.stringify(tokenizedBufferA.serialize())),
          atom
        )

        expect(tokenizedBufferB.grammar).not.toBeFalsy()
        expect(tokenizedBufferB.grammar).not.toBe(tokenizedBufferA.grammar)

        atom.grammars.addGrammar(tokenizedBufferA.grammar)

        expect(tokenizedBufferB.grammar).toBe(tokenizedBufferA.grammar)

      it "deserializes the previously selected grammar on construction when available in the grammar registry", ->
        tokenizedBufferA = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })

        tokenizedBufferA.setGrammar(atom.grammars.grammarForScopeName("source.js"))
        tokenizedBufferB = TokenizedBuffer.deserialize(
          JSON.parse(JSON.stringify(tokenizedBufferA.serialize())),
          atom
        )

        expect(tokenizedBufferB.grammar).toBe(tokenizedBufferA.grammar)

  describe "when the buffer is destroyed", ->
    beforeEach ->
      buffer = atom.project.bufferForPathSync('sample.js')
      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
      })
      startTokenizing(tokenizedBuffer)

    it "stops tokenization", ->
      tokenizedBuffer.destroy()
      spyOn(tokenizedBuffer, 'tokenizeNextChunk')
      advanceClock()
      expect(tokenizedBuffer.tokenizeNextChunk).not.toHaveBeenCalled()

  describe "when the buffer contains soft-tabs", ->
    beforeEach ->
      buffer = atom.project.bufferForPathSync('sample.js')
      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
      })
      startTokenizing(tokenizedBuffer)
      tokenizedBuffer.onDidChange changeHandler = jasmine.createSpy('changeHandler')

    afterEach ->
      tokenizedBuffer.destroy()
      buffer.release()

    describe "on construction", ->
      it "initially creates un-tokenized screen lines, then tokenizes lines chunk at a time in the background", ->
        line0 = tokenizedBuffer.tokenizedLineForRow(0)
        expect(line0.tokens).toEqual([value: line0.text, scopes: ['source.js']])

        line11 = tokenizedBuffer.tokenizedLineForRow(11)
        expect(line11.tokens).toEqual([value: "  return sort(Array.apply(this, arguments));", scopes: ['source.js']])

        # background tokenization has not begun
        expect(tokenizedBuffer.tokenizedLineForRow(0).ruleStack).toBeUndefined()

        # tokenize chunk 1
        advanceClock()
        expect(tokenizedBuffer.tokenizedLineForRow(0).ruleStack?).toBeTruthy()
        expect(tokenizedBuffer.tokenizedLineForRow(4).ruleStack?).toBeTruthy()
        expect(tokenizedBuffer.tokenizedLineForRow(5).ruleStack?).toBeFalsy()
        expect(changeHandler).toHaveBeenCalledWith(start: 0, end: 4, delta: 0)
        changeHandler.reset()

        # tokenize chunk 2
        advanceClock()
        expect(tokenizedBuffer.tokenizedLineForRow(5).ruleStack?).toBeTruthy()
        expect(tokenizedBuffer.tokenizedLineForRow(9).ruleStack?).toBeTruthy()
        expect(tokenizedBuffer.tokenizedLineForRow(10).ruleStack?).toBeFalsy()
        expect(changeHandler).toHaveBeenCalledWith(start: 5, end: 9, delta: 0)
        changeHandler.reset()

        # tokenize last chunk
        advanceClock()
        expect(tokenizedBuffer.tokenizedLineForRow(10).ruleStack?).toBeTruthy()
        expect(tokenizedBuffer.tokenizedLineForRow(12).ruleStack?).toBeTruthy()
        expect(changeHandler).toHaveBeenCalledWith(start: 10, end: 12, delta: 0)

    describe "when the buffer is partially tokenized", ->
      beforeEach ->
        # tokenize chunk 1 only
        advanceClock()
        changeHandler.reset()

      describe "when there is a buffer change inside the tokenized region", ->
        describe "when lines are added", ->
          it "pushes the invalid rows down", ->
            expect(tokenizedBuffer.firstInvalidRow()).toBe 5
            buffer.insert([1, 0], '\n\n')
            changeHandler.reset()

            expect(tokenizedBuffer.firstInvalidRow()).toBe 7
            advanceClock()
            expect(changeHandler).toHaveBeenCalledWith(start: 7, end: 11, delta: 0)

        describe "when lines are removed", ->
          it "pulls the invalid rows up", ->
            expect(tokenizedBuffer.firstInvalidRow()).toBe 5
            buffer.delete([[1, 0], [3, 0]])
            changeHandler.reset()

            expect(tokenizedBuffer.firstInvalidRow()).toBe 2
            advanceClock()
            expect(changeHandler).toHaveBeenCalledWith(start: 2, end: 6, delta: 0)

        describe "when the change invalidates all the lines before the current invalid region", ->
          it "retokenizes the invalidated lines and continues into the valid region", ->
            expect(tokenizedBuffer.firstInvalidRow()).toBe 5
            buffer.insert([2, 0], '/*')
            changeHandler.reset()
            expect(tokenizedBuffer.firstInvalidRow()).toBe 3

            advanceClock()
            expect(changeHandler).toHaveBeenCalledWith(start: 3, end: 7, delta: 0)
            expect(tokenizedBuffer.firstInvalidRow()).toBe 8

      describe "when there is a buffer change surrounding an invalid row", ->
        it "pushes the invalid row to the end of the change", ->
          buffer.setTextInRange([[4, 0], [6, 0]], "\n\n\n")
          changeHandler.reset()

          expect(tokenizedBuffer.firstInvalidRow()).toBe 8
          advanceClock()

      describe "when there is a buffer change inside an invalid region", ->
        it "does not attempt to tokenize the lines in the change, and preserves the existing invalid row", ->
          expect(tokenizedBuffer.firstInvalidRow()).toBe 5
          buffer.setTextInRange([[6, 0], [7, 0]], "\n\n\n")

          expect(tokenizedBuffer.tokenizedLineForRow(6).ruleStack?).toBeFalsy()
          expect(tokenizedBuffer.tokenizedLineForRow(7).ruleStack?).toBeFalsy()

          changeHandler.reset()
          expect(tokenizedBuffer.firstInvalidRow()).toBe 5

    describe "when the buffer is fully tokenized", ->
      beforeEach ->
        fullyTokenize(tokenizedBuffer)

      describe "when there is a buffer change that is smaller than the chunk size", ->
        describe "when lines are updated, but none are added or removed", ->
          it "updates tokens to reflect the change", ->
            buffer.setTextInRange([[0, 0], [2, 0]], "foo()\n7\n")

            expect(tokenizedBuffer.tokenizedLineForRow(0).tokens[1]).toEqual(value: '(', scopes: ['source.js', 'meta.function-call.js', 'meta.arguments.js', 'punctuation.definition.arguments.begin.bracket.round.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(1).tokens[0]).toEqual(value: '7', scopes: ['source.js', 'constant.numeric.decimal.js'])
            # line 2 is unchanged
            expect(tokenizedBuffer.tokenizedLineForRow(2).tokens[1]).toEqual(value: 'if', scopes: ['source.js', 'keyword.control.js'])

            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 0, end: 2, delta: 0)

          describe "when the change invalidates the tokenization of subsequent lines", ->
            it "schedules the invalidated lines to be tokenized in the background", ->
              buffer.insert([5, 30], '/* */')
              changeHandler.reset()
              buffer.insert([2, 0], '/*')
              expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[0].scopes).toEqual ['source.js']
              expect(changeHandler).toHaveBeenCalled()
              [event] = changeHandler.argsForCall[0]
              delete event.bufferChange
              expect(event).toEqual(start: 2, end: 2, delta: 0)
              changeHandler.reset()

              advanceClock()
              expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
              expect(tokenizedBuffer.tokenizedLineForRow(4).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
              expect(tokenizedBuffer.tokenizedLineForRow(5).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
              expect(changeHandler).toHaveBeenCalled()
              [event] = changeHandler.argsForCall[0]
              delete event.bufferChange
              expect(event).toEqual(start: 3, end: 7, delta: 0)

          it "resumes highlighting with the state of the previous line", ->
            buffer.insert([0, 0], '/*')
            buffer.insert([5, 0], '*/')

            buffer.insert([1, 0], 'var ')
            expect(tokenizedBuffer.tokenizedLineForRow(1).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']

        describe "when lines are both updated and removed", ->
          it "updates tokens to reflect the change", ->
            buffer.setTextInRange([[1, 0], [3, 0]], "foo()")

            # previous line 0 remains
            expect(tokenizedBuffer.tokenizedLineForRow(0).tokens[0]).toEqual(value: 'var', scopes: ['source.js', 'storage.type.var.js'])

            # previous line 3 should be combined with input to form line 1
            expect(tokenizedBuffer.tokenizedLineForRow(1).tokens[0]).toEqual(value: 'foo', scopes: ['source.js', 'meta.function-call.js', 'entity.name.function.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(1).tokens[6]).toEqual(value: '=', scopes: ['source.js', 'keyword.operator.assignment.js'])

            # lines below deleted regions should be shifted upward
            expect(tokenizedBuffer.tokenizedLineForRow(2).tokens[1]).toEqual(value: 'while', scopes: ['source.js', 'keyword.control.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[1]).toEqual(value: '=', scopes: ['source.js', 'keyword.operator.assignment.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(4).tokens[1]).toEqual(value: '<', scopes: ['source.js', 'keyword.operator.comparison.js'])

            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 1, end: 3, delta: -2)

        describe "when the change invalidates the tokenization of subsequent lines", ->
          it "schedules the invalidated lines to be tokenized in the background", ->
            buffer.insert([5, 30], '/* */')
            changeHandler.reset()

            buffer.setTextInRange([[2, 0], [3, 0]], '/*')
            expect(tokenizedBuffer.tokenizedLineForRow(2).tokens[0].scopes).toEqual ['source.js', 'comment.block.js', 'punctuation.definition.comment.js']
            expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[0].scopes).toEqual ['source.js']
            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 2, end: 3, delta: -1)
            changeHandler.reset()

            advanceClock()
            expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(tokenizedBuffer.tokenizedLineForRow(4).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 3, end: 7, delta: 0)

        describe "when lines are both updated and inserted", ->
          it "updates tokens to reflect the change", ->
            buffer.setTextInRange([[1, 0], [2, 0]], "foo()\nbar()\nbaz()\nquux()")

            # previous line 0 remains
            expect(tokenizedBuffer.tokenizedLineForRow(0).tokens[0]).toEqual( value: 'var', scopes: ['source.js', 'storage.type.var.js'])

            # 3 new lines inserted
            expect(tokenizedBuffer.tokenizedLineForRow(1).tokens[0]).toEqual(value: 'foo', scopes: ['source.js', 'meta.function-call.js', 'entity.name.function.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(2).tokens[0]).toEqual(value: 'bar', scopes: ['source.js', 'meta.function-call.js', 'entity.name.function.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[0]).toEqual(value: 'baz', scopes: ['source.js', 'meta.function-call.js', 'entity.name.function.js'])

            # previous line 2 is joined with quux() on line 4
            expect(tokenizedBuffer.tokenizedLineForRow(4).tokens[0]).toEqual(value: 'quux', scopes: ['source.js', 'meta.function-call.js', 'entity.name.function.js'])
            expect(tokenizedBuffer.tokenizedLineForRow(4).tokens[4]).toEqual(value: 'if', scopes: ['source.js', 'keyword.control.js'])

            # previous line 3 is pushed down to become line 5
            expect(tokenizedBuffer.tokenizedLineForRow(5).tokens[3]).toEqual(value: '=', scopes: ['source.js', 'keyword.operator.assignment.js'])

            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 1, end: 2, delta: 2)

        describe "when the change invalidates the tokenization of subsequent lines", ->
          it "schedules the invalidated lines to be tokenized in the background", ->
            buffer.insert([5, 30], '/* */')
            changeHandler.reset()

            buffer.insert([2, 0], '/*\nabcde\nabcder')
            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 2, end: 2, delta: 2)
            expect(tokenizedBuffer.tokenizedLineForRow(2).tokens[0].scopes).toEqual ['source.js', 'comment.block.js', 'punctuation.definition.comment.js']
            expect(tokenizedBuffer.tokenizedLineForRow(3).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(tokenizedBuffer.tokenizedLineForRow(4).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(tokenizedBuffer.tokenizedLineForRow(5).tokens[0].scopes).toEqual ['source.js']
            changeHandler.reset()

            advanceClock() # tokenize invalidated lines in background
            expect(tokenizedBuffer.tokenizedLineForRow(5).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(tokenizedBuffer.tokenizedLineForRow(6).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(tokenizedBuffer.tokenizedLineForRow(7).tokens[0].scopes).toEqual ['source.js', 'comment.block.js']
            expect(tokenizedBuffer.tokenizedLineForRow(8).tokens[0].scopes).not.toBe ['source.js', 'comment.block.js']

            expect(changeHandler).toHaveBeenCalled()
            [event] = changeHandler.argsForCall[0]
            delete event.bufferChange
            expect(event).toEqual(start: 5, end: 9, delta: 0)

      describe "when there is an insertion that is larger than the chunk size", ->
        it "tokenizes the initial chunk synchronously, then tokenizes the remaining lines in the background", ->
          commentBlock = _.multiplyString("// a comment\n", tokenizedBuffer.chunkSize + 2)
          buffer.insert([0, 0], commentBlock)
          expect(tokenizedBuffer.tokenizedLineForRow(0).ruleStack?).toBeTruthy()
          expect(tokenizedBuffer.tokenizedLineForRow(4).ruleStack?).toBeTruthy()
          expect(tokenizedBuffer.tokenizedLineForRow(5).ruleStack?).toBeFalsy()

          advanceClock()
          expect(tokenizedBuffer.tokenizedLineForRow(5).ruleStack?).toBeTruthy()
          expect(tokenizedBuffer.tokenizedLineForRow(6).ruleStack?).toBeTruthy()

      it "does not break out soft tabs across a scope boundary", ->
        waitsForPromise ->
          atom.packages.activatePackage('language-gfm')

        runs ->
          tokenizedBuffer.setTabLength(4)
          tokenizedBuffer.setGrammar(atom.grammars.selectGrammar('.md'))
          buffer.setText('    <![]()\n    ')
          fullyTokenize(tokenizedBuffer)

          length = 0
          for tag in tokenizedBuffer.tokenizedLines[1].tags
            length += tag if tag > 0

          expect(length).toBe 4

  describe "when the buffer contains hard-tabs", ->
    beforeEach ->
      waitsForPromise ->
        atom.packages.activatePackage('language-coffee-script')

      runs ->
        buffer = atom.project.bufferForPathSync('sample-with-tabs.coffee')
        tokenizedBuffer = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        startTokenizing(tokenizedBuffer)

    afterEach ->
      tokenizedBuffer.destroy()
      buffer.release()

    describe "when the buffer is fully tokenized", ->
      beforeEach ->
        fullyTokenize(tokenizedBuffer)

  describe "when the grammar is tokenized", ->
    it "emits the `tokenized` event", ->
      editor = null
      tokenizedHandler = jasmine.createSpy("tokenized handler")

      waitsForPromise ->
        atom.workspace.open('sample.js').then (o) -> editor = o

      runs ->
        tokenizedBuffer = editor.tokenizedBuffer
        tokenizedBuffer.onDidTokenize tokenizedHandler
        fullyTokenize(tokenizedBuffer)
        expect(tokenizedHandler.callCount).toBe(1)

    it "doesn't re-emit the `tokenized` event when it is re-tokenized", ->
      editor = null
      tokenizedHandler = jasmine.createSpy("tokenized handler")

      waitsForPromise ->
        atom.workspace.open('sample.js').then (o) -> editor = o

      runs ->
        tokenizedBuffer = editor.tokenizedBuffer
        fullyTokenize(tokenizedBuffer)

        tokenizedBuffer.onDidTokenize tokenizedHandler
        editor.getBuffer().insert([0, 0], "'")
        fullyTokenize(tokenizedBuffer)
        expect(tokenizedHandler).not.toHaveBeenCalled()

  describe "when the grammar is updated because a grammar it includes is activated", ->
    it "re-emits the `tokenized` event", ->
      editor = null
      tokenizedBuffer = null
      tokenizedHandler = jasmine.createSpy("tokenized handler")

      waitsForPromise ->
        atom.workspace.open('coffee.coffee').then (o) -> editor = o

      runs ->
        tokenizedBuffer = editor.tokenizedBuffer
        tokenizedBuffer.onDidTokenize tokenizedHandler
        fullyTokenize(tokenizedBuffer)
        tokenizedHandler.reset()

      waitsForPromise ->
        atom.packages.activatePackage('language-coffee-script')

      runs ->
        fullyTokenize(tokenizedBuffer)
        expect(tokenizedHandler.callCount).toBe(1)

    it "retokenizes the buffer", ->

      waitsForPromise ->
        atom.packages.activatePackage('language-ruby-on-rails')

      waitsForPromise ->
        atom.packages.activatePackage('language-ruby')

      runs ->
        buffer = atom.project.bufferForPathSync()
        buffer.setText "<div class='name'><%= User.find(2).full_name %></div>"
        tokenizedBuffer = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        tokenizedBuffer.setGrammar(atom.grammars.selectGrammar('test.erb'))
        fullyTokenize(tokenizedBuffer)

        {tokens} = tokenizedBuffer.tokenizedLineForRow(0)
        expect(tokens[0]).toEqual value: "<div class='name'>", scopes: ["text.html.ruby"]

      waitsForPromise ->
        atom.packages.activatePackage('language-html')

      runs ->
        fullyTokenize(tokenizedBuffer)
        {tokens} = tokenizedBuffer.tokenizedLineForRow(0)
        expect(tokens[0]).toEqual value: '<', scopes: ["text.html.ruby", "meta.tag.block.any.html", "punctuation.definition.tag.begin.html"]

  describe ".tokenForPosition(position)", ->
    afterEach ->
      tokenizedBuffer.destroy()
      buffer.release()

    it "returns the correct token (regression)", ->
      buffer = atom.project.bufferForPathSync('sample.js')
      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
      })
      fullyTokenize(tokenizedBuffer)
      expect(tokenizedBuffer.tokenForPosition([1, 0]).scopes).toEqual ["source.js"]
      expect(tokenizedBuffer.tokenForPosition([1, 1]).scopes).toEqual ["source.js"]
      expect(tokenizedBuffer.tokenForPosition([1, 2]).scopes).toEqual ["source.js", "storage.type.var.js"]

  describe ".bufferRangeForScopeAtPosition(selector, position)", ->
    beforeEach ->
      buffer = atom.project.bufferForPathSync('sample.js')
      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars,
        packageManager: atom.packages, assert: atom.assert
      })
      fullyTokenize(tokenizedBuffer)

    describe "when the selector does not match the token at the position", ->
      it "returns a falsy value", ->
        expect(tokenizedBuffer.bufferRangeForScopeAtPosition('.bogus', [0, 1])).toBeFalsy()

    describe "when the selector matches a single token at the position", ->
      it "returns the range covered by the token", ->
        expect(tokenizedBuffer.bufferRangeForScopeAtPosition('.storage.type.var.js', [0, 1])).toEqual [[0, 0], [0, 3]]
        expect(tokenizedBuffer.bufferRangeForScopeAtPosition('.storage.type.var.js', [0, 3])).toEqual [[0, 0], [0, 3]]

    describe "when the selector matches a run of multiple tokens at the position", ->
      it "returns the range covered by all contigous tokens (within a single line)", ->
        expect(tokenizedBuffer.bufferRangeForScopeAtPosition('.function', [1, 18])).toEqual [[1, 6], [1, 28]]

  describe ".indentLevelForRow(row)", ->
    beforeEach ->
      buffer = atom.project.bufferForPathSync('sample.js')
      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
      })
      fullyTokenize(tokenizedBuffer)

    describe "when the line is non-empty", ->
      it "has an indent level based on the leading whitespace on the line", ->
        expect(tokenizedBuffer.indentLevelForRow(0)).toBe 0
        expect(tokenizedBuffer.indentLevelForRow(1)).toBe 1
        expect(tokenizedBuffer.indentLevelForRow(2)).toBe 2
        buffer.insert([2, 0], ' ')
        expect(tokenizedBuffer.indentLevelForRow(2)).toBe 2.5

    describe "when the line is empty", ->
      it "assumes the indentation level of the first non-empty line below or above if one exists", ->
        buffer.insert([12, 0], '    ')
        buffer.insert([12, Infinity], '\n\n')
        expect(tokenizedBuffer.indentLevelForRow(13)).toBe 2
        expect(tokenizedBuffer.indentLevelForRow(14)).toBe 2

        buffer.insert([1, Infinity], '\n\n')
        expect(tokenizedBuffer.indentLevelForRow(2)).toBe 2
        expect(tokenizedBuffer.indentLevelForRow(3)).toBe 2

        buffer.setText('\n\n\n')
        expect(tokenizedBuffer.indentLevelForRow(1)).toBe 0

    describe "when the changed lines are surrounded by whitespace-only lines", ->
      it "updates the indentLevel of empty lines that precede the change", ->
        expect(tokenizedBuffer.indentLevelForRow(12)).toBe 0

        buffer.insert([12, 0], '\n')
        buffer.insert([13, 0], '  ')
        expect(tokenizedBuffer.indentLevelForRow(12)).toBe 1

      it "updates empty line indent guides when the empty line is the last line", ->
        buffer.insert([12, 2], '\n')

        # The newline and the tab need to be in two different operations to surface the bug
        buffer.insert([12, 0], '  ')
        expect(tokenizedBuffer.indentLevelForRow(13)).toBe 1

        buffer.insert([12, 0], '  ')
        expect(tokenizedBuffer.indentLevelForRow(13)).toBe 2
        expect(tokenizedBuffer.tokenizedLineForRow(14)).not.toBeDefined()

      it "updates the indentLevel of empty lines surrounding a change that inserts lines", ->
        # create some new lines
        buffer.insert([7, 0], '\n\n')
        buffer.insert([5, 0], '\n\n')

        expect(tokenizedBuffer.indentLevelForRow(5)).toBe 3
        expect(tokenizedBuffer.indentLevelForRow(6)).toBe 3
        expect(tokenizedBuffer.indentLevelForRow(9)).toBe 3
        expect(tokenizedBuffer.indentLevelForRow(10)).toBe 3
        expect(tokenizedBuffer.indentLevelForRow(11)).toBe 2

        tokenizedBuffer.onDidChange changeHandler = jasmine.createSpy('changeHandler')

        buffer.setTextInRange([[7, 0], [8, 65]], '        one\n        two\n        three\n        four')

        delete changeHandler.argsForCall[0][0].bufferChange
        expect(changeHandler).toHaveBeenCalledWith(start: 7, end: 8, delta: 2)

        expect(tokenizedBuffer.indentLevelForRow(5)).toBe 4
        expect(tokenizedBuffer.indentLevelForRow(6)).toBe 4
        expect(tokenizedBuffer.indentLevelForRow(11)).toBe 4
        expect(tokenizedBuffer.indentLevelForRow(12)).toBe 4
        expect(tokenizedBuffer.indentLevelForRow(13)).toBe 2

      it "updates the indentLevel of empty lines surrounding a change that removes lines", ->
        # create some new lines
        buffer.insert([7, 0], '\n\n')
        buffer.insert([5, 0], '\n\n')

        tokenizedBuffer.onDidChange changeHandler = jasmine.createSpy('changeHandler')

        buffer.setTextInRange([[7, 0], [8, 65]], '    ok')

        delete changeHandler.argsForCall[0][0].bufferChange
        expect(changeHandler).toHaveBeenCalledWith(start: 7, end: 8, delta: -1)

        expect(tokenizedBuffer.indentLevelForRow(5)).toBe 2
        expect(tokenizedBuffer.indentLevelForRow(6)).toBe 2
        expect(tokenizedBuffer.indentLevelForRow(7)).toBe 2 # new text
        expect(tokenizedBuffer.indentLevelForRow(8)).toBe 2
        expect(tokenizedBuffer.indentLevelForRow(9)).toBe 2
        expect(tokenizedBuffer.indentLevelForRow(10)).toBe 2 # }

  describe "::isFoldableAtRow(row)", ->
    changes = null

    beforeEach ->
      changes = []
      buffer = atom.project.bufferForPathSync('sample.js')
      buffer.insert [10, 0], "  // multi-line\n  // comment\n  // block\n"
      buffer.insert [0, 0], "// multi-line\n// comment\n// block\n"
      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
      })
      fullyTokenize(tokenizedBuffer)

    it "includes the first line of multi-line comments", ->
      expect(tokenizedBuffer.isFoldableAtRow(0)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(1)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(2)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(3)).toBe true # because of indent
      expect(tokenizedBuffer.isFoldableAtRow(13)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(14)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(15)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(16)).toBe false

      buffer.insert([0, Infinity], '\n')

      expect(tokenizedBuffer.isFoldableAtRow(0)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(1)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(2)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(3)).toBe false

      buffer.undo()

      expect(tokenizedBuffer.isFoldableAtRow(0)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(1)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(2)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(3)).toBe true # because of indent

    it "includes non-comment lines that precede an increase in indentation", ->
      buffer.insert([2, 0], '  ') # commented lines preceding an indent aren't foldable

      expect(tokenizedBuffer.isFoldableAtRow(1)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(2)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(3)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(4)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(5)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(6)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(7)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(8)).toBe false

      buffer.insert([7, 0], '  ')

      expect(tokenizedBuffer.isFoldableAtRow(6)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(7)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(8)).toBe false

      buffer.undo()

      expect(tokenizedBuffer.isFoldableAtRow(6)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(7)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(8)).toBe false

      buffer.insert([7, 0], "    \n      x\n")

      expect(tokenizedBuffer.isFoldableAtRow(6)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(7)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(8)).toBe false

      buffer.insert([9, 0], "  ")

      expect(tokenizedBuffer.isFoldableAtRow(6)).toBe true
      expect(tokenizedBuffer.isFoldableAtRow(7)).toBe false
      expect(tokenizedBuffer.isFoldableAtRow(8)).toBe false

  describe "when the buffer is configured with the null grammar", ->
    it "uses the placeholder tokens and does not actually tokenize using the grammar", ->
      spyOn(atom.grammars.nullGrammar, 'tokenizeLine').andCallThrough()
      buffer = atom.project.bufferForPathSync('sample.will-use-the-null-grammar')
      buffer.setText('a\nb\nc')

      tokenizedBuffer = new TokenizedBuffer({
        buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
      })
      tokenizeCallback = jasmine.createSpy('onDidTokenize')
      tokenizedBuffer.onDidTokenize(tokenizeCallback)

      fullyTokenize(tokenizedBuffer)

      expect(tokenizeCallback.callCount).toBe 1
      expect(atom.grammars.nullGrammar.tokenizeLine.callCount).toBe 0

      expect(tokenizedBuffer.tokenizedLineForRow(0).tokens.length).toBe 1
      expect(tokenizedBuffer.tokenizedLineForRow(0).tokens[0].value).toBe 'a'
      expect(tokenizedBuffer.tokenizedLineForRow(1).tokens.length).toBe 1
      expect(tokenizedBuffer.tokenizedLineForRow(1).tokens[0].value).toBe 'b'
      expect(tokenizedBuffer.tokenizedLineForRow(2).tokens.length).toBe 1
      expect(tokenizedBuffer.tokenizedLineForRow(2).tokens[0].value).toBe 'c'

  describe 'when a file is opened', ->
    [registration, editor, called] = []
    beforeEach ->
      runs ->
        called = false
        registration = atom.packages.onDidTriggerActivationHook('language-javascript:grammar-used', -> called = true)

      waitsForPromise ->
        atom.workspace.open('sample.js', autoIndent: false).then (o) ->
          editor = o

      waitsForPromise ->
        atom.packages.activatePackage('language-javascript')

    afterEach: ->
      registration?.dispose?()
      atom.packages.deactivatePackages()
      atom.packages.unloadPackages()

    it 'triggers the grammar-used hook', ->
      waitsFor ->
        called is true

      runs ->
        expect(called).toBe true

    describe 'when changing the grammar of an open file', ->
      [coffeeRegistration, coffeeCalled] = []

      beforeEach ->
        coffeeCalled = false
        coffeeRegistration = atom.packages.onDidTriggerActivationHook('language-coffee-script:grammar-used', -> coffeeCalled = true)

        waitsForPromise ->
          atom.packages.activatePackage('language-coffee-script')

      afterEach ->
        coffeeRegistration?.dispose()

      it 'triggers the grammar-used hook', ->
        waitsFor ->
          called is true

        runs ->
          expect(called).toBe true
          expect(coffeeCalled).toBe false
          editor.setGrammar(atom.grammars.selectGrammar('.coffee'))

        waitsFor ->
          coffeeCalled is true

        runs ->
          expect(coffeeCalled).toBe true

  describe "text decoration layer API", ->
    describe "iterator", ->
      it "iterates over the syntactic scope boundaries", ->
        buffer = new TextBuffer(text: "var foo = 1 /*\nhello*/var bar = 2\n")
        tokenizedBuffer = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        tokenizedBuffer.setGrammar(atom.grammars.selectGrammar(".js"))
        fullyTokenize(tokenizedBuffer)

        iterator = tokenizedBuffer.buildIterator()
        iterator.seek(Point(0, 0))

        expectedBoundaries = [
          {position: Point(0, 0), closeTags: [], openTags: ["source.js", "storage.type.var.js"]}
          {position: Point(0, 3), closeTags: ["storage.type.var.js"], openTags: []}
          {position: Point(0, 8), closeTags: [], openTags: ["keyword.operator.assignment.js"]}
          {position: Point(0, 9), closeTags: ["keyword.operator.assignment.js"], openTags: []}
          {position: Point(0, 10), closeTags: [], openTags: ["constant.numeric.decimal.js"]}
          {position: Point(0, 11), closeTags: ["constant.numeric.decimal.js"], openTags: []}
          {position: Point(0, 12), closeTags: [], openTags: ["comment.block.js", "punctuation.definition.comment.js"]}
          {position: Point(0, 14), closeTags: ["punctuation.definition.comment.js"], openTags: []}
          {position: Point(1, 5), closeTags: [], openTags: ["punctuation.definition.comment.js"]}
          {position: Point(1, 7), closeTags: ["punctuation.definition.comment.js", "comment.block.js"], openTags: ["storage.type.var.js"]}
          {position: Point(1, 10), closeTags: ["storage.type.var.js"], openTags: []}
          {position: Point(1, 15), closeTags: [], openTags: ["keyword.operator.assignment.js"]}
          {position: Point(1, 16), closeTags: ["keyword.operator.assignment.js"], openTags: []}
          {position: Point(1, 17), closeTags: [], openTags: ["constant.numeric.decimal.js"]}
          {position: Point(1, 18), closeTags: ["constant.numeric.decimal.js"], openTags: []}
        ]

        loop
          boundary = {
            position: iterator.getPosition(),
            closeTags: iterator.getCloseTags(),
            openTags: iterator.getOpenTags()
          }

          expect(boundary).toEqual(expectedBoundaries.shift())
          break unless iterator.moveToSuccessor()

        expect(iterator.seek(Point(0, 1))).toEqual(["source.js", "storage.type.var.js"])
        expect(iterator.getPosition()).toEqual(Point(0, 3))
        expect(iterator.seek(Point(0, 8))).toEqual(["source.js"])
        expect(iterator.getPosition()).toEqual(Point(0, 8))
        expect(iterator.seek(Point(1, 0))).toEqual(["source.js", "comment.block.js"])
        expect(iterator.getPosition()).toEqual(Point(1, 0))
        expect(iterator.seek(Point(1, 18))).toEqual(["source.js", "constant.numeric.decimal.js"])
        expect(iterator.getPosition()).toEqual(Point(1, 18))

        expect(iterator.seek(Point(2, 0))).toEqual(["source.js"])
        iterator.moveToSuccessor() # ensure we don't infinitely loop (regression test)

      it "does not report columns beyond the length of the line", ->
        waitsForPromise ->
          atom.packages.activatePackage('language-coffee-script')

        runs ->
          buffer = new TextBuffer(text: "# hello\n# world")
          tokenizedBuffer = new TokenizedBuffer({
            buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
          })
          tokenizedBuffer.setGrammar(atom.grammars.selectGrammar(".coffee"))
          fullyTokenize(tokenizedBuffer)

          iterator = tokenizedBuffer.buildIterator()
          iterator.seek(Point(0, 0))
          iterator.moveToSuccessor()
          iterator.moveToSuccessor()
          expect(iterator.getPosition().column).toBe(7)

          iterator.moveToSuccessor()
          expect(iterator.getPosition().column).toBe(0)

          iterator.seek(Point(0, 7))
          expect(iterator.getPosition().column).toBe(7)

          iterator.seek(Point(0, 8))
          expect(iterator.getPosition().column).toBe(7)

      it "correctly terminates scopes at the beginning of the line (regression)", ->
        grammar = atom.grammars.createGrammar('test', {
          'scopeName': 'text.broken'
          'name': 'Broken grammar'
          'patterns': [
            {'begin': 'start', 'end': '(?=end)', 'name': 'blue.broken'},
            {'match': '.', 'name': 'yellow.broken'}
          ]
        })

        buffer = new TextBuffer(text: 'start x\nend x\nx')
        tokenizedBuffer = new TokenizedBuffer({
          buffer, config: atom.config, grammarRegistry: atom.grammars, packageManager: atom.packages, assert: atom.assert
        })
        tokenizedBuffer.setGrammar(grammar)
        fullyTokenize(tokenizedBuffer)

        iterator = tokenizedBuffer.buildIterator()
        iterator.seek(Point(1, 0))

        expect(iterator.getPosition()).toEqual([1, 0])
        expect(iterator.getCloseTags()).toEqual ['blue.broken']
        expect(iterator.getOpenTags()).toEqual ['yellow.broken']
