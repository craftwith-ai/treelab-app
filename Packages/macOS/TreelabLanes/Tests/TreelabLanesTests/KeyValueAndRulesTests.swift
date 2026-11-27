import Foundation
import Testing

@testable import TreelabLanes

@Suite("Reading lab's KEY=value text")
struct KeyValueBlockParserTests {
    @Test("blocks split on blank lines, repeated keys kept in order, stray lines skipped")
    func blocks() {
        let text = "PROJECT=demo\nLANE=api\nWATCH=/a\nWATCH=/b\nnot a field\nlower=skip\n\nPROJECT=demo\r\nLANE=web\r\n"
        let blocks = KeyValueBlockParser().blocks(in: text)
        #expect(blocks.count == 2)
        #expect(blocks[0].all("WATCH") == ["/a", "/b"])
        #expect(blocks[0].first("lower") == nil)
        #expect(blocks[1].first("LANE") == "web")
    }

    @Test("a value keeps every character after the first equals sign")
    func valueKept() {
        let block = KeyValueBlockParser().blocks(in: "WHY=a=b; $(rm -rf ~) \"x\"\n").first
        #expect(block?.first("WHY") == "a=b; $(rm -rf ~) \"x\"")
    }

    @Test("a lane block reads every field lab writes")
    func laneRecord() throws {
        let block = try #require(KeyValueBlockParser().blocks(in: """
        PROJECT=demo
        LANE=api
        WAITS_FOR=you
        WHY=question waiting: Claude is waiting for your input
        SESSION=live
        BATCH=lot-02-api
        BATCH_STATE=in progress
        FOR_YOU=yes
        WAKE_AT=1800000000
        WATCH=/r/.worktrees/api/.lab/meta
        WRITTEN=/r/.worktrees/api/.lab/waits-for
        WATCH_PID=4242
        """).first)
        let lane = try #require(LaneRecord(block: block))
        #expect(lane.id == "demo/api")
        #expect(lane.forYou && lane.sessionLive)
        #expect(lane.wakeAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(lane.watchPIDs == [4242])
        #expect(lane.metaPath == "/r/.worktrees/api/.lab/meta")
        #expect(lane.waitsForPath == "/r/.worktrees/api/.lab/waits-for")
        #expect(LaneRecord(block: KeyValueBlock(entries: [.init(key: "PROJECT", value: "demo")])) == nil)
    }
}

@Suite("The rule of the states (batches 05 to 08)")
struct LaneStatusRuleTests {
    let rule = LaneStatusRule()

    @Test("FOR_YOU=yes is waiting for you, whatever else")
    func waiting() {
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: "you", sessionLive: true, forYou: true)) == .waitingForYou)
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: "acceptance", forYou: true)) == .waitingForYou)
    }

    @Test("a date or a permanent lane at rest is outside the counter")
    func offCounter() {
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: "date")) == .offCounter)
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: "date", sessionLive: true)) == .offCounter)
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", permanent: true)) == .offCounter)
    }

    @Test("a live session, or CI, merge, close and acceptance handled by the tower, is working")
    func working() {
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", sessionLive: true)) == .working)
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", sessionLive: true, permanent: true)) == .working)
        for waits in ["ci", "merge", "close", "acceptance"] {
            #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: waits)) == .working)
        }
    }

    @Test("no session and nothing in progress is stopped")
    func stopped() {
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: "nothing")) == .stopped)
        #expect(rule.status(of: LaneRecord(project: "p", lane: "l", waitsFor: "you", forYou: false)) == .stopped)
    }

    @Test("the kind of a request comes from lab's WHY and WAITS_FOR")
    func kinds() {
        func kind(_ why: String, _ waits: String = "you") -> RequestKind {
            RequestKind.of(LaneRecord(project: "p", lane: "l", waitsFor: waits, why: why, forYou: true))
        }
        #expect(kind("question waiting: Claude is waiting for your input") == .question)
        #expect(kind("permission requested: Bash") == .permission)
        #expect(kind("work finished, to try together") == .toTry)
        #expect(kind("", "acceptance") == .toTry)
        #expect(kind("lane blocked: red CI") == .blocked)
        #expect(kind("next step to clarify") == .toClarify)
        #expect(kind("closing: say yes") == .closing)
        #expect(kind("something new") == .other)
    }
}

@Suite("Counter, indicators and Feed order")
struct LanesSnapshotBuilderTests {
    @Test("the counter is the sum of the indicators, projects by name, requests oldest first")
    func snapshot() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let lanes = [
            LaneRecord(project: "zeta", lane: "b", waitsFor: "you", why: "permission requested", sessionLive: true, forYou: true, waitingSince: t0.addingTimeInterval(60)),
            LaneRecord(project: "zeta", lane: "a", sessionLive: true),
            LaneRecord(project: "alpha", lane: "c", waitsFor: "you", why: "question waiting", sessionLive: true, forYou: true, waitingSince: t0),
            LaneRecord(project: "alpha", lane: "d"),
            LaneRecord(project: "alpha", lane: "e", waitsFor: "date"),
            LaneRecord(project: "alpha", lane: "f", waitsFor: "you", why: "lane blocked", forYou: true),
            LaneRecord(project: "alpha", lane: "g", waitsFor: "merge"),
        ]
        let projects = [ProjectRecord(project: "zeta", root: "/z"), ProjectRecord(project: "alpha", root: "/a"), ProjectRecord(project: "empty", root: "/e")]
        let snapshot = LanesSnapshotBuilder().snapshot(projects: projects, lanes: lanes, labVersion: "1.8.2")
        #expect(snapshot.projects.map(\.id) == ["alpha", "empty", "zeta"])
        let alpha = snapshot.projects[0].counts
        #expect(alpha == StatusCounts(waitingForYou: 2, working: 1, stopped: 1, offCounter: 1))
        #expect(snapshot.projects[1].counts.counted == 0)
        #expect(snapshot.total == snapshot.projects.reduce(StatusCounts()) { $0 + $1.counts })
        #expect(snapshot.total.counted == 6)
        #expect(snapshot.requests.map(\.id) == ["alpha/c", "zeta/b", "alpha/f"])
        #expect(snapshot.requests.map(\.kind) == [.question, .permission, .blocked])
        #expect(snapshot.lanes(.stopped).map(\.id) == ["alpha/d"])
        #expect(snapshot.lanes(.offCounter).map(\.id) == ["alpha/e"])
    }

    @Test("a lane whose project file is missing still counts, under its project name")
    func orphanLane() {
        let snapshot = LanesSnapshotBuilder().snapshot(projects: [], lanes: [LaneRecord(project: "p", lane: "l")], labVersion: nil)
        #expect(snapshot.projects.map(\.id) == ["p"])
        #expect(snapshot.total.stopped == 1)
    }
}

@Suite("What a lane asks")
struct LabQuestionTests {
    @Test("a box reads every question, choice, description, multiple and recommended")
    func box() throws {
        let block = try #require(KeyValueBlockParser().blocks(in: """
        LANE=api
        WAITS=box
        QID=q-17
        QUESTION_1=Where do settings open?
        OPTION_1_1=Separate window
        DESC_1_1=Hides the lane
        OPTION_1_2=In a tab
        DESC_1_2=Beside the lane
        RECOMMENDED_1=1
        QUESTION_2=Which themes?
        MULTI_2=yes
        OPTION_2_1=HUD
        OPTION_2_2=Black
        """).first)
        guard case let .box(qid, items) = LabQuestion.parse(block) else { Issue.record("not a box"); return }
        #expect(qid == "q-17")
        #expect(items.count == 2)
        #expect(items[0].options.map(\.label) == ["Separate window", "In a tab"])
        #expect(items[0].options[1].detail == "Beside the lane")
        #expect(items[0].recommended == "1")
        #expect(items[1].multiple)
        #expect(!items[0].multiple)
    }

    @Test("a message or nothing")
    func messageAndNone() {
        let parser = KeyValueBlockParser()
        #expect(LabQuestion.parse(parser.blocks(in: "WAITS=message\nMESSAGE=Shall I go on?\n")[0]) == .message("Shall I go on?"))
        #expect(LabQuestion.parse(parser.blocks(in: "WAITS=none\n")[0]) == .none)
        #expect(LabQuestion.parse(parser.blocks(in: "WAITS=box\nQUESTION_1=x\n")[0]) == .none)
    }
}
