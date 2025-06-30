const std = @import("std");
const print = std.debug.print;

// English letter frequency (from most to least common)
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
};

const Feedback = enum {
    green, // correct letter in correct position
    yellow, // correct letter in wrong position
    grey, // letter not in word at all
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var solver = WordleSolver.init(allocator);
    defer solver.deinit();

    try solver.loadWords("solutions.txt");

    print("{s}{s}🎯 WORDLE SOLVER 🎯{s}\n", .{ Colors.BOLD, Colors.CYAN, Colors.RESET });
    print("{s}Commands:{s}\n", .{ Colors.BOLD, Colors.RESET });
    print("  {s}suggest{s}             - Get a word suggestion\n", .{ Colors.GREEN, Colors.RESET });
    print("  {s}feedback <word> <code>{s} - Enter feedback ({s}g{s}=green, {s}y{s}=yellow, {s}b/r{s}=grey)\n", .{ Colors.GREEN, Colors.RESET, Colors.GREEN, Colors.RESET, Colors.YELLOW, Colors.RESET, Colors.GREY, Colors.RESET });
    print("  {s}show{s}                - Show possible words\n", .{ Colors.GREEN, Colors.RESET });
    print("  {s}quit{s}                - Exit\n\n", .{ Colors.GREEN, Colors.RESET });

    const stdin = std.io.getStdIn().reader();
    var buf: [256]u8 = undefined;

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
                    print("{s}❌ Feedback must be 5 characters ({s}g{s}=green, {s}y{s}=yellow, {s}b/r{s}=grey){s}\n", .{ Colors.YELLOW, Colors.GREEN, Colors.YELLOW, Colors.YELLOW, Colors.YELLOW, Colors.GREY, Colors.YELLOW, Colors.RESET });
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

    print("{s}👋 Goodbye!{s}\n", .{ Colors.CYAN, Colors.RESET });
}
