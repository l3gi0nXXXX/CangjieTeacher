package cangjie_teacher_test

import std.unittest.testmacro.*
import cangjie_teacher.*

class S2FailingFixtureExecutor <: TeacherAssetFixtureExecutor {
    public func executorKind(): String { "fake_contract" }
    public func providerIdentityHash(): String { "sha256:${teacherStableHash("fake")}" }
    public func modelVersion(): String { "fake-scaffold-v1" }
    public func execute(fixture: TeacherAssetFixture): (Int64, String, String) {
        (1, "different", "synthetic failure transcript")
    }
}

public func s2Fixtures(): Array<TeacherAssetFixture> {
    [
        TeacherAssetFixture("positive-rune", "positive", "non_humaneval_experiment",
            "Render 中文🙂 at a Rune boundary.", "positive_passed"),
        TeacherAssetFixture("negative-byte", "negative", "non_humaneval_experiment",
            "Reject splitting one encoded Rune.", "negative_rejected"),
        TeacherAssetFixture("boundary-max", "boundary", "non_humaneval_experiment",
            "Accept the exact UTF-8 byte budget.", "boundary_passed"),
        TeacherAssetFixture("generalization-label", "generalization", "non_humaneval_experiment",
            "Apply the invariant to a generic label renderer.", "generalization_passed")
    ]
}

@Test
public class TeacherFailureAssetTestExecutorTest {
    @TestCase public func failureAssetFixtureResultsComeOnlyFromExecutor(): Unit {
        let results = executeTeacherAssetFixtureBundle(s2Fixtures(), FakeTeacherAssetFixtureExecutor())
        @Expect(results.size, 4)
        for (result in results) {
            @Expect(result.passed, true)
            @Expect(renderTeacherAssetFixtureExecution(result).contains("\"executorKind\":\"fake_contract\""), true)
        }
        let failed = executeTeacherAssetFixtureBundle([s2Fixtures()[0]], S2FailingFixtureExecutor())
        @Expect(failed[0].passed, false)
        @Expect(renderTeacherAssetFixtureExecution(failed[0]).contains("\"passed\":false"), true)
        var benchmarkRejected = ""
        try { _ = executeTeacherAssetFixtureBundle([TeacherAssetFixture("bad", "unit", "non_humaneval_experiment",
            "CJ-HUMANEVAL-007 hidden_test", "passed")], FakeTeacherAssetFixtureExecutor()) }
        catch (e: Exception) { benchmarkRejected = e.message }
        @Expect(benchmarkRejected, "candidate_test_evidence_invalid")
    }
}
