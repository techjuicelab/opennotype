#!/usr/bin/env python3
"""합성 faithful 재시작 fixture의 보조 검사를 검증합니다. API·키·모델 호출은 없습니다."""
import importlib.util
from pathlib import Path
import re
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('faithful_restart_textbench', ROOT / 'scripts/compare-text-models.py')
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)
FIXTURE = ROOT / 'docs/fixtures/faithful-restarts.json'


class FaithfulRestartFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.network_guard = patch.object(BENCH.transport, 'post_once', side_effect=AssertionError('fixture tests must not access the network'))
        cls.network_guard.start()
        cls.cases, cls.fixture_hash = BENCH.load_cases(FIXTURE, None)
        cls.by_id = {case['id']: case for case in cls.cases}

    @classmethod
    def tearDownClass(cls):
        cls.network_guard.stop()

    def failed_checks(self, id, text):
        return {check['name'] for check in BENCH.quality_checks(self.by_id[id], text) if not check['passed']}

    def test_all_sixteen_cases_use_existing_faithful_dictation(self):
        self.assertEqual(len(self.cases), 16)
        self.assertEqual(set(self.by_id), {f'FR{i:02d}' for i in range(1, 17)})
        for case in self.cases:
            with self.subTest(id=case['id']):
                self.assertEqual(case['mode'], 'dictation')
                self.assertEqual(case['writing_profile'], {'kind': 'general', 'tone': 'preserve', 'expression': {'style': 'faithful', 'strength': 0}})
                self.assertIsNone(BENCH.fixture_expression(case))
                self.assertTrue(case['manual_semantic_review_required'])
                self.assertTrue(case['preservation_conditions'])
                self.assertTrue(case['cleanup_conditions'])
                self.assertTrue(case['forbidden_changes'])
                self.assertEqual(len({check['name'] for check in case['checks']}), len(case['checks']))
        self.assertEqual({case['language'] for case in self.cases}, {'ko', 'en', 'ko-en'})

    def test_human_authored_examples_satisfy_production_benchmark_checks(self):
        for case in self.cases:
            with self.subTest(id=case['id']):
                self.assertEqual(self.failed_checks(case['id'], case['expected_text']), set())

    def test_user_example_and_intended_name_reference_reduction_are_explicit(self):
        case = self.by_id['FR01']
        self.assertEqual(case['stt_input'], '나는 A를 개발하고 싶어서 B 를 리서치 하고 있어요. B 를 리서치 하고 있는데요.. 음.. 그런데 말이죠.. 음.. B를 리서치할때 또 필요한것이 C인데요.')
        self.assertEqual(case['expected_text'], '나는 A를 개발하고 싶어서 B를 리서치하고 있어요. 그런데 B를 리서치할 때 또 필요한 것이 C인데요.')
        counts = {item['name']: (item['source_count'], item['example_output_count']) for item in case['reference_counts']}
        self.assertEqual(counts, {'A': (1, 1), 'B': (3, 2), 'C': (1, 1)})

    def test_reference_metadata_agrees_with_source_and_example_without_imposing_counts_on_meaning(self):
        for case in self.cases:
            for item in case['reference_counts']:
                with self.subTest(id=case['id'], name=item['name']):
                    pattern = r'(?<![A-Za-z0-9_])' + re.escape(item['name']) + r'(?![A-Za-z0-9_])'
                    self.assertEqual(item['source_count'], len(re.findall(pattern, case['stt_input'], re.I)))
                    self.assertEqual(item['example_output_count'], len(re.findall(pattern, case['expected_text'], re.I)))
                    self.assertGreater(item['source_count'], 0)
                    self.assertGreater(item['example_output_count'], 0)
                    self.assertIn('독립 명제', item['rule'])
        product_case = {item['name']: (item['source_count'], item['example_output_count']) for item in self.by_id['FR02']['reference_counts']}
        self.assertEqual(product_case['OpenNoType'], (3, 2))
        self.assertEqual(product_case['JEV'], (2, 1))

    def test_known_cleanup_and_semantic_regressions_are_detected(self):
        example = {id: case['expected_text'] for id, case in self.by_id.items()}
        mutations = [
            ('FR01', self.by_id['FR01']['stt_input'], 'B redundant mentions removed'),
            ('FR01', '나는 A를 개발하고 싶어서 B를 리서치하고 있어요.', 'C name'),
            ('FR01', example['FR01'].replace('그런데', '그리고'), 'Contrast not weakened to plain listing'),
            ('FR02', example['FR02'].replace('개선하고 싶어요', '개선해 주세요'), 'Improvement remains a wish'),
            ('FR03', example['FR03'].replace('5달러', '50달러'), 'Five dollars'),
            ('FR04', 'B를 리서치하고 있어요. 한국어가 지원되면 도입해 주세요.', 'Above budget prohibits adoption'),
            ('FR05', example['FR05'].replace('호출하지 마세요', '호출해 주세요'), 'Payment API prohibited'),
            ('FR06', example['FR06'].replace('3번', '2번'), 'Retries corrected to three'),
            ('FR06', example['FR06'].replace('30초', '3초'), 'Total thirty seconds'),
            ('FR07', example['FR07'].replace('정말 정말', '정말'), 'Deliberate urgency emphasis'),
            ('FR08', example['FR08'].replace('10:30', '10:00'), 'Second error time'),
            ('FR08', example['FR08'].replace('Retry once', 'Retry twice'), 'Retry once after second error'),
            ('FR09', 'JEV로 OpenNoType을 개선하고 문장 검토부터 하고 싶어요. 저는 결과를 보고 싶어요.', 'Review remains request'),
            ('FR10', example['FR10'].replace('지원하나요?', '지원해요.'), 'Support remains a question'),
            ('FR11', example['FR11'].replace('retry retry', 'retry'), 'Literal quoted repetition'),
            ('FR11', example['FR11'].replace('`B_B`', '`B`'), 'Exact identifier'),
            ('FR12', 'I am researching B to develop A.', 'C name'),
            ('FR13', example['FR13'].replace('I want JEV to improve OpenNoType.', 'Improve OpenNoType with JEV.'), 'Improvement remains personal wish'),
            ('FR13', example['FR13'].replace('If approved,', 'After review,'), 'Approved sending condition'),
            ('FR14', example['FR14'].replace(', but only if approved', ''), 'Approval required'),
            ('FR14', example['FR14'].replace('Keep the original version.', ''), 'Keep original version'),
            ('FR15', example['FR15'].replace('제부', 'JEV'), 'Keep family term in Hangul'),
            ('FR16', example['FR16'].replace('좀 ', ''), 'Hedge kept'),
            ('FR16', example['FR16'].replace('기다리고 싶어요', '기다려 주세요'), 'Waiting remains wish'),
        ]
        for id, text, required_failure in mutations:
            with self.subTest(id=id, check=required_failure):
                self.assertIn(required_failure, self.failed_checks(id, text))

    def test_numeric_checks_reject_larger_values_containing_the_same_digits(self):
        cases = [
            ('FR03', '5달러', '15달러', 'Five dollars'),
            ('FR03', '5달러', '50달러', 'Five dollars'),
            ('FR04', '5달러', '15달러', 'Five dollar limit'),
            ('FR06', '10초', '110초', 'Timeout ten seconds'),
            ('FR06', '10초', '삼십초', 'Timeout ten seconds'),
            ('FR06', '3번', '13번', 'Retries corrected to three'),
            ('FR06', '30초', '130초', 'Total thirty seconds'),
            ('FR08', '10:00', '110:00', 'First error time'),
            ('FR13', '3 pm', '13 pm', 'Three pm'),
        ]
        for id, old, new, failure in cases:
            with self.subTest(id=id, mutated=new):
                self.assertIn(failure, self.failed_checks(id, self.by_id[id]['expected_text'].replace(old, new)))

    def test_equivalent_spoken_numbers_and_korean_attached_digits_are_allowed(self):
        examples = [
            ('FR03', 'B를 리서치하고 있어요. 비용은 매달 다섯 달러까지 괜찮아요.'),
            ('FR06', 'timeout은 십 초예요. 재시도는 세 번만 해 주세요. 총 제한 시간은 삼십 초예요.'),
            ('FR06', 'timeout은10초예요. 재시도는3번만 해 주세요. 총 제한 시간은30초예요.'),
            ('FR08', self.by_id['FR08']['expected_text'].replace('twice,', 'two times,').replace('Retry once', 'Retry one time')),
            ('FR13', self.by_id['FR13']['expected_text'].replace('3 pm', 'three p.m.')),
        ]
        for id, text in examples:
            with self.subTest(id=id, text=text):
                self.assertEqual(self.failed_checks(id, text), set())

    def test_shorter_output_cannot_pass_by_dropping_all_communicative_content(self):
        for case in self.cases:
            with self.subTest(id=case['id']):
                self.assertTrue(self.failed_checks(case['id'], ''))


if __name__ == '__main__':
    unittest.main()
