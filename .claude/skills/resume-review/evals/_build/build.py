"""Generate resume-review eval cases from the repository's README.md and detail.md.

Each case seeds known defects into a copy of the resume, writes it into the run's
empty workspace through a scaffold script, and grades whether the review caught them.
Re-run after editing the resume: python3 .claude/skills/resume-review/evals/_build/build.py
"""

import shutil
from pathlib import Path

EVALS = Path(__file__).resolve().parent.parent
REPO = EVALS.parents[3]
HEREDOC = "__RESUME_EOF__"

# file, old, new, expected count
SEEDS = {
    "d1-blame": [(
        "detail.md",
        "Laravelのモデルに処理が密結合し、テストがほぼ無い状態でした。",
        "前任者の設計が雑だったせいで、Laravelのモデルに処理が密結合し、テストもまともに書かれていない状態でした。",
        1,
    )],
    "e1-leave-reason": [(
        "README.md",
        "- 放送大学の情報コースで学んでいます。\n",
        "- 放送大学の情報コースで学んでいます。\n- 現職は評価制度に納得できず、上司とも折り合いが悪いため転職を考えています。\n",
        1,
    )],
    "b4-inconsistency": [(
        "README.md",
        "2025年10月に初回リリースしました。",
        "2025年8月に初回リリースしました。",
        2,
    )],
    "c3-agency": [(
        "detail.md",
        "役割として頼まれたものではありません。事業部に必要だと判断し、自分から取り組みました。",
        "事業部の方針として、生成AIの活用推進を担当しました。",
        1,
    )],
    "c4-numbers": [(
        "detail.md",
        "画面表示時間を10秒から2秒に短縮しました。",
        "画面表示を高速化しました。",
        1,
    )],
    "c6-user-info": [
        (
            "detail.md",
            "- 観察: 実際の検索クエリを私が確認しました。\n"
            "  利用者は短く簡単な検索語しか入力しておらず、想定した検索精度が出ていませんでした。",
            "- 観察: 想定した検索精度が出ていませんでした。",
            1,
        ),
        (
            "README.md",
            "実際の検索クエリを確認し、利用者が短い検索語しか入力しないという設計上の課題を特定しました。",
            "検索精度に課題があることが分かりました。",
            1,
        ),
        (
            "README.md",
            "実際の検索クエリを確認し、利用者が短い検索語しか入力しないという課題を見つけました。",
            "検索精度に課題があることが分かりました。",
            1,
        ),
    ],
    "t-eval-none": [
        (
            "detail.md",
            "- 評価には、既存の人手によるタグ付けデータを評価セットとして使いました。\n"
            "  人手で付けたタグを正解としてLLMに判定させ、その結果を私が確認しました。\n",
            "",
            1,
        ),
        ("README.md", "人手のタグを正解にした評価の仕組みまで本番環境に構築しました。", "本番環境に構築しました。", 1),
        ("README.md", " / 評価セット（人手タグとの比較）", "", 1),
    ],
    "b4-team-size": [(
        "detail.md",
        "PM 1名と、私を含むエンジニア5名（うち業務委託2名）です。",
        "PM 1名と、私を含むエンジニア4名（うち業務委託2名）です。",
        1,
    )],
    "c3-designer": [(
        "detail.md",
        "設計と判断は私が行っています。",
        "設計と判断はPMが行い、私は実装を担当しています。",
        1,
    )],
    "c8-scope": [(
        "detail.md",
        "を、2026年9月に事業部で開催しました。\n",
        "を、2026年9月に事業部で開催しました。これにより、事業部の全業務フローをAIエージェント前提に再設計しました。\n",
        1,
    )],
    "c8-overclaim": [(
        "detail.md",
        "2026年9月に完成させました。\n  - 計測項目は",
        "2026年9月に完成させました。これにより事業部全体の生産性が3倍になりました。\n  - 計測項目は",
        1,
    )],
}

# What a correct review must say about each seed (llm grader rubric).
EXPECT = {
    "d1-blame": "「前任者の設計が雑だったせいで」という記述を、他人のせいにしている(他罰的)と指摘し、状況説明への書き換えを提案している",
    "e1-leave-reason": "「評価制度に納得できず、上司とも折り合いが悪い」という記述を、退職理由・不満を公開の経歴書に書いている問題(ネガティブな転職理由、公開すべきでない情報)として指摘している",
    "b4-inconsistency": "初回リリース時期がREADME.md(2025年8月)とdetail.md(2025年10月)で食い違っていることを指摘している",
    "c3-agency": "生成AI活用推進の取り組みが「事業部の方針として担当した」としか書かれておらず、本人の判断・主体性が見えないこと、またはREADME.mdの「頼まれる前に自分から進めました」と矛盾していることを指摘している",
    "c4-numbers": "衛星画像の分析支援Webアプリ(株式会社スタッフサービスの職歴)に数字がないことを、指摘として、または判定表でその職歴のC4を不足(×)とすることで示している",
    "c6-user-info": "素材の自然言語検索で「検索精度に課題がある」とする根拠(利用者のクエリや行動をどう観察して課題を特定したか)が書かれていないことを指摘している",
    "t-eval-none": "台本・動画のAIタグ付けについて、出力の品質を確かめた手段(評価)が一つも書かれていないことを指摘している。評価セットの件数・合否の基準・一致率などの詳細が足りないことだけを言うものは該当しない",
    "b4-team-size": "広告配信プラットフォームのエンジニア人数が、記載箇所によって5名と4名で食い違っていることを指摘している",
    "c3-designer": "動画広告ASP事業向けLLM機能で「設計と判断はPMが行い、私は実装を担当」とdetail.mdにある一方、README.mdでは本人が設計から担当していると書かれており、役割の記述が矛盾していることを指摘している",
    "c8-scope": "AWSのAI BPRワークショップの開催によって「事業部の全業務フローをAIエージェント前提に再設計した」という主張が、ワークショップ1回の成果としては過大で根拠がないことを指摘している",
    "c8-overclaim": "「事業部全体の生産性が3倍になりました」という主張に、測定方法・根拠がなく、面接で崩れる・盛りに見えることを指摘している",
}

PERSONA_CASES = {
    "d1-blame": "checklist",
    "e1-leave-reason": "checklist",
    "b4-inconsistency": "screener",
    "c3-agency": "hiring-manager",
    # C2(理由の削除)は置かない。どの理由を消しても、Minorとして枠から落ちるか正直な開示として良い点に読まれ、検出が揺らぐ
    # 古い職歴の数字の欠落はMinorで、上位10件に絞るペルソナでは落ちる。全項目を当てるchecklistで測る
    "c4-numbers": "checklist",
    "c6-user-info": "business",
    "c8-overclaim": "interviewer",
    "b4-team-size": "screener",
    "c3-designer": "hiring-manager",
    "c8-scope": "interviewer",
    # 評価の記述の削除。スキルなしでも拾える(3/3)ので、回帰の検知用
    "t-eval-none": "interviewer",
    # 人の確認の記述の削除は置かない。スキルあり・なしとも気づかなかった(0/1、0/3)
}

# Cases where a serious seed must rank near the top while a minor seed is also present.
PRIORITY_CASES = {
    "priority-c3-over-c4": ("c3-designer", ["c4-numbers"]),
}

FULL_CASES = {
    "full-e1-c8": ["e1-leave-reason", "c8-overclaim"],
    "full-b4-c4": ["b4-inconsistency", "c4-numbers"],
}


def seeded(seed_names):
    files = {name: (REPO / name).read_text() for name in ("README.md", "detail.md")}
    for seed in seed_names:
        for file, old, new, count in SEEDS[seed]:
            found = files[file].count(old)
            if found != count:
                raise SystemExit(f"{seed}: expected {count} match(es) in {file}, found {found}: {old[:40]!r}")
            files[file] = files[file].replace(old, new)
    return files


def fixture_script(files):
    parts = ["#!/usr/bin/env bash", "set -euo pipefail"]
    for name, text in files.items():
        if HEREDOC in text:
            raise SystemExit(f"{name} contains the heredoc delimiter")
        parts.append(f"cat > {name} <<'{HEREDOC}'\n{text.rstrip(chr(10))}\n{HEREDOC}")
    return "\n".join(parts) + "\n"


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def write_case(name, files, prompt, graders, tags, max_turns, timeout):
    case = EVALS / name
    write(case / "fixture.sh", fixture_script(files))
    (case / "fixture.sh").chmod(0o755)
    write(case / "case.yaml", f'schema_version: "1.1"\nname: {name}\ncontext:\n  scaffold_script: fixture.sh\n')
    tag_list = ", ".join(tags)
    write(case / "prompt.md", (
        "---\n"
        f"tags: [{tag_list}]\n"
        f"max_turns: {max_turns}\n"
        f"timeout_seconds: {timeout}\n"
        "allowed_tools: [Read, Glob, Grep, Skill, Agent]\n"
        "---\n\n"
        f"{prompt}\n"
    ))
    for grader_name, body in graders.items():
        write(case / "graders" / f"{grader_name}.md", body)


SKILL_FIRED = (
    "---\n"
    "type: tool_used\n"
    "tool: Skill\n"
    "input_match: '\"skill\"\\s*:\\s*\"(?:[\\w-]+:)?resume-review\"'\n"
    "---\n"
)


def agent_count(minimum, maximum=None):
    upper = f"max: {maximum}\n" if maximum is not None else ""
    return f"---\ntype: tool_used\ntool: Agent\nmin: {minimum}\n{upper}arm: with-only\n---\n"


def caught(seed):
    return (
        "---\ntype: llm\nfocus: last_message\n---\n\n"
        f"PASS if the review {EXPECT[seed]}.\n"
        "Wording may differ; judge by meaning. The finding may appear anywhere in the response.\n"
        "FAIL if no finding addresses this point, or the point is mentioned only as a strength.\n"
    )


def main():
    for case in EVALS.iterdir():
        if case.is_dir() and not case.name.startswith("_") and case.name != "results":
            shutil.rmtree(case)
    for seed, persona in PERSONA_CASES.items():
        write_case(
            f"persona-{persona}-{seed}",
            seeded([seed]),
            f"この職務経歴書(README.md と detail.md)をレビューして。今回は persona={persona} の観点だけでいい。",
            {"caught": caught(seed), "skill-fired": SKILL_FIRED, "one-reviewer": agent_count(1, 1)},
            ["persona", persona],
            max_turns=40,
            timeout=900,
        )
    for name, seeds in FULL_CASES.items():
        graders = {f"caught-{seed}": caught(seed) for seed in seeds}
        graders["skill-fired"] = SKILL_FIRED
        graders["all-reviewers"] = agent_count(6)
        write_case(
            name,
            seeded(seeds),
            "この職務経歴書(README.md と detail.md)を多角的にレビューして。",
            graders,
            ["full"],
            max_turns=60,
            timeout=1800,
        )
    for name, (major, minors) in PRIORITY_CASES.items():
        write_case(
            name,
            seeded([major, *minors]),
            "この職務経歴書(README.md と detail.md)を多角的にレビューして。",
            {
                "ranked-top3": (
                    "---\ntype: llm\nfocus: last_message\n---\n\n"
                    f"Look only at the first three findings in the prioritized list of findings.\n"
                    f"PASS if one of those three findings {EXPECT[major]}.\n"
                    "FAIL if that point appears only after the third finding, or not at all.\n"
                ),
                "skill-fired": SKILL_FIRED,
                "all-reviewers": agent_count(6),
            },
            ["full", "priority"],
            max_turns=60,
            timeout=1800,
        )
    write_case(
        "control-original",
        seeded([]),
        "この職務経歴書(README.md と detail.md)を多角的にレビューして。",
        {
            "no-false-alarm": (
                "---\ntype: llm\nfocus: last_message\n---\n\n"
                "The resume under review does not state any reason for leaving a job or any complaint about "
                "the current employer.\n"
                "PASS unless the review asserts that the resume already contains such a statement, for example by "
                "quoting a sentence as a reason for leaving or a complaint.\n"
                "Advice not to write reasons for leaving, warnings that something could be read as a reason for "
                "leaving, and remarks that a sentence could be read as blaming someone are all PASS.\n"
                "FAIL only if the review claims the resume explicitly states a reason for leaving or a complaint "
                "about the employer.\n"
            ),
            "skill-fired": SKILL_FIRED,
            "all-reviewers": agent_count(6),
        },
        ["full", "control"],
        max_turns=60,
        timeout=1800,
    )


if __name__ == "__main__":
    main()
