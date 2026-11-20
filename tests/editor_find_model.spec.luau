--!strict

do
	local find = Apps.EditorFindModel
	local bounded = find.Search(string.rep("a ", 2000), "a", { MaxMatches = 100 })
	assert(
		#bounded.Matches == 100 and bounded.Truncated,
		"global search caps retained matches before building an unbounded result list"
	)
	local exact = find.Search("a a", "a", { MaxMatches = 2 })
	assert(#exact.Matches == 2 and not exact.Truncated, "exact limits do not falsely report missing results")
	local checks = 0
	local cancelled = find.Search(string.rep("a ", 2000), "a", {
		Checkpoint = function()
			checks += 1
			return false
		end,
	})
	assert(
		cancelled.Cancelled and #cancelled.Matches == 256 and checks == 1,
		"long literal matching cooperates with cancellation"
	)
	local boundedRegex = find.Search(string.rep("a ", 200), "a", { Regex = true, MaxMatches = 10 })
	assert(#boundedRegex.Matches == 10 and boundedRegex.Truncated, "regex results obey the same retained result cap")
	local result = find.Search("Cat cat scatter cat_ cat.", "cat")
	assert(
		#result.Matches == 5 and result.Matches[1].Start == 1 and result.Matches[1].Finish == 4,
		"literal matches use exclusive UTF-8 byte offsets"
	)
	assert(
		#find.Search("Cat cat scatter cat_ cat.", "cat", { MatchCase = true, WholeWord = true }).Matches == 2,
		"case and whole-word filtering compose"
	)
	assert(#find.Search("a.b axb a%b", "a.b").Matches == 1, "literal punctuation is never interpreted as a pattern")
	assert(
		#find.Search("cat cat cat", "cat", { Scope = { Start = 5, Finish = 8 } }).Matches == 1,
		"selection scope includes only complete contained matches"
	)
	assert(
		#find.Search("cat cat cat", "cat", { Scope = { Start = 8, Finish = 5 } }).Matches == 1,
		"backward selection scopes normalize"
	)
	assert(#find.Search("anything", "", {}).Matches == 0, "empty literal query has no zero-length loop")
	do
		local text = string.rep("a", 200) .. " Cat 猫cat cat. cat_ cats CATnot " .. string.rep(" cat", 150)
		local opts = { WholeWord = true, Scope = { Start = 202, Finish = 225 } }
		local hits = find.Search(text, "cat", opts).Matches
		assert(#hits == 2 and hits[1].Start == 202 and hits[1].Finish == 205 and text:sub(hits[2].Start - 1, hits[2].Finish) == " cat.")
		opts.Scope = { Start = hits[2].Start, Finish = hits[2].Finish - 1 }
		assert(#find.Search(text, "cat", opts).Matches == 0)
		opts.Scope = { Start = 209, Finish = 215 }
		assert(#find.Search(text, "cat", opts).Matches == 0, "word boundaries include neighboring text outside the scope")
	end
	assert(find.SupportsRegex, "the real regex dependency is available")
	local regex = find.Search("foo12 bar34 foo5", "(foo|bar)(\\d+)", { Regex = true, MatchCase = true })
	assert(
		not regex.Error
			and #regex.Matches == 3
			and regex.Matches[2].Groups[1] == "bar"
			and regex.Matches[2].Groups[2] == "34",
		"real regex supports alternation, groups and digit quantifiers"
	)
	assert(
		#find.Search("CAT cat", "cat", { Regex = true }).Matches == 2
			and #find.Search("CAT cat", "cat", { Regex = true, MatchCase = true }).Matches == 1,
		"regex case flags actually control matching"
	)
	local words = find.Search("cat scatter cat_ cat.", "\\bcat\\b", { Regex = true })
	assert(not words.Error and #words.Matches == 2, "regex word boundaries compare adjacent word classifications")
	local unicodeRegex = find.Search("猫é猫", "猫", { Regex = true })
	assert(
		not unicodeRegex.Error
			and #unicodeRegex.Matches == 2
			and unicodeRegex.Matches[2].Start == 6
			and unicodeRegex.Matches[2].Finish == 9,
		"regex codepoint spans convert to UTF-8 insertion offsets"
	)
	local named = find.Search("abc12", "(?<word>[a-z]+)(\\d+)", { Regex = true })
	assert(
		not named.Error
			and #named.Matches == 1
			and find.Replace("abc12", named.Matches[1], "${word} $$ $&").Text == "abc $ abc12",
		"named captures and escaped dollar replacement work"
	)
	local lazy = find.Search("<a><b>", "<.*?>", { Regex = true })
	assert(not lazy.Error and #lazy.Matches == 2, "regex lazy quantifiers preserve separate shortest matches")
	local backref = find.Search("aa ab bb", "([a-z])\\1", { Regex = true })
	assert(not backref.Error and #backref.Matches == 2, "regex backreferences compare captured source")
	assert(
		find.ReplaceAll("foo12 bar34 foo5", regex.Matches, "$2:$1").Text == "12:foo 34:bar 5:foo",
		"regex replacement expands capture groups"
	)
	assert(find.Search("foo", "[", { Regex = true }).Error, "malformed regex reports an error")
	assert(
		find.Search(string.rep("a", 200) .. "!", "(a+)+$", { Regex = true, WorkLimit = 100 }).Error,
		"pathological backtracking stops at the work limit"
	)
	local anchors = find.Search("foo\nbar\nfoo", "^foo$", { Regex = true })
	assert(not anchors.Error and #anchors.Matches == 2, "regex anchors operate on document lines")
	local look = find.Search("xxfoobar", "(?<=foo)bar", { Regex = true, Scope = { Start = 6, Finish = 9 } })
	assert(
		not look.Error and #look.Matches == 1 and look.Matches[1].Start == 6,
		"selection scope preserves regex lookbehind context"
	)
	local zeros = find.Search("ab", "(?=.)", { Regex = true })
	assert(
		not zeros.Error and #zeros.Matches == 2 and find.ReplaceAll("ab", zeros.Matches, "!").Text == "!a!b",
		"zero-width regex progresses and replaces safely"
	)
	local matches = find.Search("cat xx cat xx cat", "cat").Matches
	local index, wrapped = find.Step(matches, 5, false)
	assert(index == 2 and not wrapped, "forward search starts from the nearest match after the caret")
	index, wrapped = find.Step(matches, 8, true)
	assert(index == 1 and not wrapped, "backward search starts before the caret")
	index, wrapped = find.Step(matches, 99, false)
	assert(index == 1 and wrapped, "forward search wraps")
	index, wrapped = find.Step(matches, 1, true)
	assert(index == 3 and wrapped, "backward search wraps")
	index, wrapped = find.Step(matches, 1, false, 3)
	assert(index == 1 and wrapped, "current selected match is advanced exactly once")
	assert(find.Step({}, 1, false) == nil, "empty result has no selected match")
	local replaced = find.Replace("cat cat", matches[1], "$1%")
	assert(
		replaced.Text == "$1% cat" and replaced.Caret == 4 and replaced.Count == 1,
		"replacement text remains literal"
	)
	local all = find.ReplaceAll("cat xx cat xx cat", matches, "X")
	assert(
		all.Text == "X xx X xx X" and all.Count == 3 and all.Caret == 12,
		"replace all maps final caret through prior edits"
	)
	assert(
		find.ReplaceAll("abc", { { Start = 1, Finish = 3 }, { Start = 2, Finish = 4 } }, "x").Error,
		"overlapping replacement is rejected atomically"
	)
	local unicode = find.Search("猫 é 猫", "猫")
	assert(#unicode.Matches == 2 and unicode.Matches[2].Start == 8, "Unicode literal results retain byte offsets")
	assert(
		find.ReplaceAll("猫 é 猫", unicode.Matches, "狗").Text == "狗 é 狗",
		"Unicode replacement preserves complete sequences"
	)
	local empty = find.ReplaceAll("ab", { { Start = 1, Finish = 1 }, { Start = 3, Finish = 3 } }, "!")
	assert(empty.Text == "!ab!" and empty.Count == 2, "explicit zero-length matches terminate safely")
	print(
		"PASS: editor literal/regex find, captures, scope, wrapped navigation, Unicode, replacement and bounded backtracking"
	)
end
