const std = @import("std");
const print = std.debug.print;

// English letter frequencies (from most to least common)
const LETTER_FREQUENCIES = "etaoinshrdlcumwfgypbvkjxqz";

// Color codes for terminal output
const Colors = struct {
    const RESET = "\x1b[0m";
    const GREEN = "\x1b[32m";
    const YELLOW = "\x1b[33m";
    const GREY = "\x1b[90m";
    const BLUE = "\x1b[34m";
    const CYAN = "\x1b[36m";
    const BOLD = "\x1b[1m";
    const RED = "\x1b[31m";
};

const Feedback = enum {
    green, // correct letter in correct position
    yellow, // correct letter in wrong position
    grey, // letter not in word at all
};

const AppMode = enum {
    solver,
    art_tool,
};

const WordleSolver = struct {
    words: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .words = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.words.items) |word| {
            self.allocator.free(word);
        }
        self.words.deinit();
    }

    pub fn loadWords(self: *Self, filename: []const u8) !void {
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
            print("Error opening file: {}\n", .{err});
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const contents = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(contents);

        _ = try file.readAll(contents);

        // split by lines, trim, store as lowercase
        var lines = std.mem.splitSequence(u8, contents, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\n\t");
            if (trimmed.len == 5) {
                const word = try self.allocator.dupe(u8, trimmed);
                for (word) |*char| {
                    char.* = std.ascii.toLower(char.*);
                }
                try self.words.append(word);
            }
        }

        print("{s}✓ Loaded {} words{s}\n", .{ Colors.GREEN, self.words.items.len, Colors.RESET });
    }

    pub fn filterWords(self: *Self, guess: []const u8, feedback: [5]Feedback) !void {
        var new_words = std.ArrayList([]const u8).init(self.allocator);

        for (self.words.items) |word| {
            if (self.isWordValid(word, guess, feedback)) {
                try new_words.append(word);
            } else {
                self.allocator.free(word);
            }
        }

        self.words.deinit();
        self.words = new_words;

        if (self.words.items.len > 0) {
            print("{s}→ {} words remaining{s}\n", .{ Colors.BLUE, self.words.items.len, Colors.RESET });
        } else {
            print("{s}⚠ No words remaining!{s}\n", .{ Colors.YELLOW, Colors.RESET });
        }
    }

    fn isWordValid(self: *Self, word: []const u8, guess: []const u8, feedback: [5]Feedback) bool {
        _ = self;

        for (feedback, 0..) |fb, i| {
            switch (fb) {
                .green => {
                    if (word[i] != guess[i]) return false;
                },
                .yellow => {
                    if (word[i] == guess[i]) return false;
                    if (!std.mem.containsAtLeast(u8, word, 1, guess[i .. i + 1])) return false;
                },
                .grey => {
                    var should_contain = false;
                    for (feedback, 0..) |other_fb, j| {
                        if (i != j and guess[j] == guess[i] and
                            (other_fb == .green or other_fb == .yellow))
                        {
                            should_contain = true;
                            break;
                        }
                    }

                    if (!should_contain and std.mem.containsAtLeast(u8, word, 1, guess[i .. i + 1])) {
                        return false;
                    }
                },
            }
        }

        return true;
    }

    // Calculate feedback when comparing a guess with the target answer
    pub fn calculateFeedback(guess: []const u8, answer: []const u8) [5]Feedback {
        var feedback: [5]Feedback = [_]Feedback{.grey} ** 5;
        var used = [_]bool{false} ** 5;

        // First pass: find green matches
        for (0..5) |i| {
            if (guess[i] == answer[i]) {
                feedback[i] = .green;
                used[i] = true;
            }
        }

        // Second pass: find yellow matches
        for (0..5) |i| {
            if (feedback[i] == .grey) {
                for (0..5) |j| {
                    if (!used[j] and guess[i] == answer[j]) {
                        feedback[i] = .yellow;
                        used[j] = true;
                        break;
                    }
                }
            }
        }

        return feedback;
    }

    // Find words that produce a specific feedback pattern when compared with the answer
    pub fn findWordsThatMatch(self: *Self, answer: []const u8, desired_feedback: [5]Feedback) !std.ArrayList([]const u8) {
        var matches = std.ArrayList([]const u8).init(self.allocator);

        for (self.words.items) |word| {
            const feedback = calculateFeedback(word, answer);
            
            var is_match = true;
            for (feedback, desired_feedback) |actual, desired| {
                if (actual != desired) {
                    is_match = false;
                    break;
                }
            }
            
            if (is_match) {
                try matches.append(try self.allocator.dupe(u8, word));
            }
        }

        return matches;
    }

    fn hasRepeatedLetters(word: []const u8) bool {
        var seen: [26]bool = [_]bool{false} ** 26;
        for (word) |char| {
            const index = char - 'a';
            if (seen[index]) return true;
            seen[index] = true;
        }
        return false;
    }

    fn getLetterFrequencyScore(word: []const u8) f32 {
        var score: f32 = 0;
        var unique_letters: [26]bool = [_]bool{false} ** 26;

        for (word) |char| {
            const index = char - 'a';
            if (!unique_letters[index]) {
                unique_letters[index] = true;
                // Find position in frequency table (lower index = higher frequency)
                for (LETTER_FREQUENCIES, 0..) |freq_char, pos| {
                    if (freq_char == char) {
                        score += @as(f32, @floatFromInt(26 - pos));
                        break;
                    }
                }
            }
        }
        return score;
    }

    pub fn getSuggestion(self: *Self) ?[]const u8 {
        if (self.words.items.len == 0) return null;
        if (self.words.items.len == 1) return self.words.items[0];

        var best_word: ?[]const u8 = null;
        var best_score: f32 = -1;

        for (self.words.items) |word| {
            var score = getLetterFrequencyScore(word);

            // Bonus for words without repeated letters
            if (!hasRepeatedLetters(word)) {
                score += 10.0;
            }

            if (score > best_score) {
                best_score = score;
                best_word = word;
            }
        }

        return best_word;
    }

    pub fn showPossibleWords(self: *Self, max_count: usize) void {
        const count = @min(max_count, self.words.items.len);
        print("{s}Possible words ({}):{s} ", .{ Colors.CYAN, self.words.items.len, Colors.RESET });

        for (self.words.items[0..count], 0..) |word, i| {
            if (i > 0) print(", ", .{});

            // Highlight words without repeated letters
            if (!hasRepeatedLetters(word)) {
                print("{s}{s}{s}", .{ Colors.BOLD, word, Colors.RESET });
            } else {
                print("{s}", .{word});
            }
        }

        if (self.words.items.len > max_count) {
            print(" {s}... and {} more{s}", .{ Colors.GREY, self.words.items.len - max_count, Colors.RESET });
        }
        print("\n", .{});
    }
};

fn parseFeedback(input: []const u8) ![5]Feedback {
    if (input.len != 5) return error.InvalidFeedback;

    var feedback: [5]Feedback = undefined;
    for (input, 0..) |char, i| {
        feedback[i] = switch (char) {
            'g', 'G' => .green,
            'y', 'Y' => .yellow,
            'b', 'B', 'r', 'R' => .grey,
            else => return error.InvalidFeedback,
        };
    }

    return feedback;
}

fn printFeedbackInfo() void {
    print("\n{s}Feedback Guide:{s}\n", .{ Colors.BOLD, Colors.RESET });
    print("  {s}g{s} or {s}G{s} = {s}GREEN{s} (correct letter, correct position)\n", .{ Colors.GREEN, Colors.RESET, Colors.GREEN, Colors.RESET, Colors.GREEN, Colors.RESET });
    print("  {s}y{s} or {s}Y{s} = {s}YELLOW{s} (correct letter, wrong position)\n", .{ Colors.YELLOW, Colors.RESET, Colors.YELLOW, Colors.RESET, Colors.YELLOW, Colors.RESET });
    print("  {s}b{s}, {s}r{s}, {s}B{s} or {s}R{s} = {s}GREY{s} (letter not in word)\n", .{ Colors.GREY, Colors.RESET, Colors.GREY, Colors.RESET, Colors.GREY, Colors.RESET, Colors.GREY, Colors.RESET, Colors.GREY, Colors.RESET });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var solver = WordleSolver.init(allocator);
    defer solver.deinit();

    try solver.loadWords("solutions.txt");

    print("{s}{s}🎮 WORDLE TOOLKIT 🎮{s}\n", .{ Colors.BOLD, Colors.CYAN, Colors.RESET });
    print("Choose mode:\n", .{});
    print("  {s}1{s} - Wordle Solver (help solve a puzzle)\n", .{ Colors.GREEN, Colors.RESET });
    print("  {s}2{s} - Wordle Art Tool (find words that create specific patterns)\n", .{ Colors.BLUE, Colors.RESET });
    
    const stdin = std.io.getStdIn().reader();
    var buf: [256]u8 = undefined;
    
    print("\n{s}Choose mode (1 or 2):{s} ", .{ Colors.BOLD, Colors.RESET });
    
    const mode: AppMode = blk: {
        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \r\n");
            if (std.mem.eql(u8, trimmed, "2")) {
                break :blk .art_tool;
            }
        }
        break :blk .solver; // Default to solver
    };
    
    switch (mode) {
        .solver => try runSolverMode(&solver, stdin, &buf),
        .art_tool => try runArtToolMode(&solver, stdin, &buf),
    }

    print("{s}👋 Goodbye!{s}\n", .{ Colors.CYAN, Colors.RESET });
}

fn runSolverMode(solver: *WordleSolver, stdin: std.fs.File.Reader, buf: *[256]u8) !void {
    print("\n{s}{s}🎯 WORDLE SOLVER MODE 🎯{s}\n", .{ Colors.BOLD, Colors.CYAN, Colors.RESET });
    print("{s}Commands:{s}\n", .{ Colors.BOLD, Colors.RESET });
    print("  {s}suggest{s}             - Get a word suggestion\n", .{ Colors.GREEN, Colors.RESET });
    print("  {s}feedback <word> <code>{s} - Enter feedback ({s}g{s}=green, {s}y{s}=yellow, {s}b/r{s}=grey)\n", .{ Colors.GREEN, Colors.RESET, Colors.GREEN, Colors.RESET, Colors.YELLOW, Colors.RESET, Colors.GREY, Colors.RESET });
    print("  {s}show{s}                - Show possible words\n", .{ Colors.GREEN, Colors.RESET });
    print("  {s}quit{s}                - Exit\n\n", .{ Colors.RED, Colors.RESET });

    printFeedbackInfo();

    // Suggest initial word
    if (solver.getSuggestion()) |suggestion| {
        print("{s}💡 Suggested starting word: {s}{s}{s}\n", .{ Colors.BOLD, Colors.CYAN, suggestion, Colors.RESET });
    }

    while (true) {
        print("{s}>{s} ", .{ Colors.BOLD, Colors.RESET });

        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \r\n");

            if (std.mem.eql(u8, trimmed, "quit")) {
                break;
            } else if (std.mem.eql(u8, trimmed, "suggest")) {
                if (solver.getSuggestion()) |suggestion| {
                    print("{s}💡 Suggested word: {s}{s}{s}\n", .{ Colors.BOLD, Colors.CYAN, suggestion, Colors.RESET });
                } else {
                    print("{s}❌ No words remaining!{s}\n", .{ Colors.YELLOW, Colors.RESET });
                }
            } else if (std.mem.eql(u8, trimmed, "show")) {
                solver.showPossibleWords(10);
            } else if (std.mem.startsWith(u8, trimmed, "feedback ")) {
                // Parse "feedback word gygyr" format
                var parts = std.mem.splitScalar(u8, trimmed[9..], ' ');
                const word = parts.next() orelse {
                    print("{s}Usage: feedback <word> <feedback>{s}\n", .{ Colors.YELLOW, Colors.RESET });
                    continue;
                };
                const feedback_str = parts.next() orelse {
                    print("{s}Usage: feedback <word> <feedback>{s}\n", .{ Colors.YELLOW, Colors.RESET });
                    continue;
                };

                if (word.len != 5) {
                    print("{s}❌ Word must be 5 letters{s}\n", .{ Colors.YELLOW, Colors.RESET });
                    continue;
                }

                const feedback = parseFeedback(feedback_str) catch {
                    printFeedbackInfo();
                    continue;
                };

                try solver.filterWords(word, feedback);

                if (solver.getSuggestion()) |suggestion| {
                    print("{s}💡 Next suggestion: {s}{s}{s}\n", .{ Colors.BOLD, Colors.CYAN, suggestion, Colors.RESET });
                } else {
                    print("{s}❌ No valid words found! Check your feedback.{s}\n", .{ Colors.YELLOW, Colors.RESET });
                }
            } else {
                print("{s}❓ Unknown command. Type '{s}quit{s}' to exit.{s}\n", .{ Colors.YELLOW, Colors.GREEN, Colors.YELLOW, Colors.RESET });
            }
        }
    }
}

fn runArtToolMode(solver: *WordleSolver, stdin: std.fs.File.Reader, buf: *[256]u8) !void {
    print("\n{s}{s}🎨 WORDLE ART TOOL MODE 🎨{s}\n", .{ Colors.BOLD, Colors.BLUE, Colors.RESET });
    print("This mode helps you find words that create specific patterns against a target word.\n\n", .{});
    
    print("Enter the target answer word: ", .{});
    const answer = blk: {
        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \r\n");
            if (trimmed.len != 5) {
                print("{s}❌ Word must be exactly 5 letters. Using 'hello' as default.{s}\n", .{ Colors.YELLOW, Colors.RESET });
                break :blk "hello";
            }
            var word_buf: [5]u8 = undefined;
            for (trimmed, 0..) |char, i| {
                word_buf[i] = std.ascii.toLower(char);
            }
            break :blk word_buf[0..5];
        } else {
            print("{s}❌ Using 'hello' as default answer.{s}\n", .{ Colors.YELLOW, Colors.RESET });
            break :blk "hello";
        }
    };

    print("\n{s}Target word set to: {s}{s}{s}\n", .{ Colors.BOLD, Colors.CYAN, answer, Colors.RESET });
    print("{s}Instructions:{s}\n", .{ Colors.BOLD, Colors.RESET });
    print("  • Enter a pattern like {s}GBGBG{s} to find words that create that pattern\n", .{ Colors.CYAN, Colors.RESET });
    print("  • Type {s}quit{s} to exit\n\n", .{ Colors.RED, Colors.RESET });
    
    printFeedbackInfo();

    while (true) {
        print("\n{s}Enter desired pattern (e.g., GBBGY) or 'quit':{s} ", .{ Colors.BOLD, Colors.RESET });

        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
            const trimmed = std.mem.trim(u8, input, " \r\n");

            if (std.mem.eql(u8, trimmed, "quit")) {
                break;
            }

            const desired_feedback = parseFeedback(trimmed) catch {
                print("{s}❌ Invalid pattern format. Pattern must be 5 characters using G, Y, B/R.{s}\n", .{ Colors.YELLOW, Colors.RESET });
                printFeedbackInfo();
                continue;
            };

            // Find words that produce this pattern
            var matches = try solver.findWordsThatMatch(answer, desired_feedback);
            defer {
                for (matches.items) |word| {
                    solver.allocator.free(word);
                }
                matches.deinit();
            }

            if (matches.items.len == 0) {
                print("{s}❌ No words found that produce this pattern against '{s}'.{s}\n", .{ Colors.YELLOW, answer, Colors.RESET });
            } else {
                print("{s}✓ Found {} words that produce this pattern against '{s}':{s}\n", .{ Colors.GREEN, matches.items.len, answer, Colors.RESET });
                
                const show_count = @min(matches.items.len, 10);
                for (matches.items[0..show_count], 0..) |word, i| {
                    if (i > 0 and i % 5 == 0) print("\n", .{});
                    print("{s}{}{s}. {s}", .{ Colors.CYAN, i + 1, Colors.RESET, word });
                    
                    if (i < show_count - 1) {
                        print("  ", .{});
                    }
                }
                print("\n", .{});
                
                if (matches.items.len > 10) {
                    print("{s}... and {} more words{s}\n", .{ Colors.GREY, matches.items.len - 10, Colors.RESET });
                }
            }
        }
    }
}
