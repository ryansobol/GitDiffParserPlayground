import RegexBuilder

struct GitDiffHunkHeader: CustomStringConvertible {
	let lineStartPrev: Int
	let lineCountPrev: Int
	let lineStartNext: Int
	let lineCountNext: Int
	let sectionHeading: String

	init(
		lineStartPrev: Int,
		lineCountPrev: Int?,
		lineStartNext: Int,
		lineCountNext: Int?,
		sectionHeading: String
	) {
		self.lineStartPrev = lineStartPrev
		self.lineCountPrev = lineCountPrev ?? 1
		self.lineStartNext = lineStartNext
		self.lineCountNext = lineCountNext ?? 1
		self.sectionHeading = sectionHeading
	}

	var description: String {
		"@@ -\(lineStartPrev),\(lineCountPrev) +\(lineStartNext),\(lineCountNext) @@\(sectionHeading.isEmpty ? "" : " \(sectionHeading)")"
	}
}

struct GitDiffHunkLine: CustomStringConvertible {
	enum Prefix: Character {
		case addition = "+"
		case deletion = "-"
		case noNewline = #"\"#
		case unchanged = " "
	}

	let content: String
	let prefix: Prefix

	var description: String {
		"\(prefix.rawValue)\(content)"
	}
}

struct GitDiffHunk: CustomStringConvertible {
	let header: GitDiffHunkHeader
	let lines: [GitDiffHunkLine]
	
	var description: String {
		header.description + "\n" + lines.map { $0.description }.joined(separator: "\n")
	}
}

struct GitDiffParser {
	enum Error: Swift.Error {
		case invalidFormat(String)
	}

	private let gitHunkHeaderRegex = Regex {
		Anchor.startOfSubject
		"@@ -"
		Capture {
			OneOrMore(.digit)
		} transform: {
			Int($0)!
		}
		Optionally {
			","
			Capture {
				OneOrMore(.digit)
			} transform: {
				Int($0)!
			}
		}
		" +"
		Capture {
			OneOrMore(.digit)
		} transform: {
			Int($0)!
		}
		Optionally {
			","
			Capture {
				OneOrMore(.digit)
			} transform: {
				Int($0)!
			}
		}
		" @@"
		Optionally(" ")
		Capture {
			ZeroOrMore(.anyNonNewline)
		} transform: {
			String($0)
		}
		Anchor.endOfLine
		One(.newlineSequence)
	}

	private let gitHunkLineRegex = Regex {
		Anchor.startOfLine
		Capture {
			ChoiceOf {
				"+"
				"-"
				" "
			}
		} transform: {
			GitDiffHunkLine.Prefix(rawValue: $0.first!)!
		}
		Capture {
			ZeroOrMore(.anyNonNewline)
		} transform: {
			String($0)
		}
		Anchor.endOfLine
		Optionally(.newlineSequence)
	}

	private let gitHunkLineNoNewlineRegex = Regex {
		Anchor.startOfLine
		Capture {
			#"\"#
		} transform: { _ in
			GitDiffHunkLine.Prefix.noNewline
		}
		Capture {
			" No newline at end of file"
		} transform: {
			String($0)
		}
		Anchor.endOfLine
		Optionally(.newlineSequence)
	}

	func parse(_ gitDiff: String) throws -> [GitDiffHunk] {
		var gitDiffSlice = Substring(gitDiff)
		var hunkHeader: GitDiffHunkHeader? = nil
		var hunkLines: [GitDiffHunkLine] = []
		var hunks: [GitDiffHunk] = []

		while !gitDiffSlice.isEmpty {
			if let match = try gitHunkLineRegex.prefixMatch(in: gitDiffSlice) {
				let (matchSlice, prefix, content) = match.output

				hunkLines.append(GitDiffHunkLine(content: content, prefix: prefix))

				gitDiffSlice = gitDiffSlice.suffix(from: matchSlice.endIndex)

				continue
			}

			if let match = try gitHunkHeaderRegex.prefixMatch(in: gitDiffSlice) {
				if let header = hunkHeader {
					hunks.append(GitDiffHunk(header: header, lines: hunkLines))

					hunkHeader = nil
					hunkLines = []
				}

				let (
					matchSlice,
					lineStartPrev,
					lineCountPrev,
					lineStartNext,
					lineCountNext,
					sectionHeading
				) = match.output

				hunkHeader = GitDiffHunkHeader(
					lineStartPrev: lineStartPrev,
					lineCountPrev: lineCountPrev,
					lineStartNext: lineStartNext,
					lineCountNext: lineCountNext,
					sectionHeading: sectionHeading
				)

//				TODO: Measure the performance of geometric array reallocation for large git diffs, and consider optimizing by pre-emptively reserving capacity
//				if let hunkHeader = hunkHeader {
//					hunkLines.reserveCapacity(max(hunkHeader.lineCountPrev, hunkHeader.lineCountNext))
//				}

				gitDiffSlice = gitDiffSlice.suffix(from: matchSlice.endIndex)

				continue
			}

			if let match = try gitHunkLineNoNewlineRegex.prefixMatch(in: gitDiffSlice) {
				let (matchSlice, prefix, content) = match.output

				hunkLines.append(GitDiffHunkLine(content: content, prefix: prefix))

				gitDiffSlice = gitDiffSlice.suffix(from: matchSlice.endIndex)

				continue
			}

			throw Error.invalidFormat(
				"Invalid format for git diff: \(String(gitDiffSlice).debugDescription)"
			)
		}

		if let hunkHeader = hunkHeader {
			hunks.append(GitDiffHunk(header: hunkHeader, lines: hunkLines))
		}

		return hunks
	}
}

let gitDiffParser = GitDiffParser()

let hunks = try gitDiffParser.parse(#"""
	@@ -73,6 +73,23 @@
	     - uses: actions/checkout@v4
	     - name: ${{ matrix.name }}
	       run: make test_SPM test_install_SPM
	+  SPMSQLCipher:
	+    name: SPM
	+    runs-on: ${{ matrix.runsOn }}
	+    env:
	+      DEVELOPER_DIR: "/Applications/${{ matrix.xcode }}/Contents/Developer"
	+    timeout-minutes: 60
	+    strategy:
	+      fail-fast: false
	+      matrix:
	+        include:
	+          - xcode: "Xcode_16.1.app"
	+            runsOn: macOS-14
	+            name: "Xcode 16.1"
	+    steps:
	+      - uses: actions/checkout@v4
	+      - name: ${{ matrix.name }}
	+        run: GRDBCIPHER="https://github.com/skiptools/swift-sqlcipher.git#1.2.1" swift test
	 SQLCipher3:
	   name: SQLCipher3
	   runs-on: ${{ matrix.runsOn }}
	@@ -141,4 +158,4 @@ jobs:
	     - uses: actions/checkout@v4
	     - name: ${{ matrix.name }}
	       run: make test_universal_xcframework
	-    
	\ No newline at end of file
	+    
	"""#)

for hunk in hunks {
	print(hunk)
}
