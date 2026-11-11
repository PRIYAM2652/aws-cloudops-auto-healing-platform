import importlib.util
import json
import os
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).parents[1]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / "src" / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FunctionTests(unittest.TestCase):
    def test_healthy_response(self):
        module = load("demo_app", "app.py")
        fake = mock.Mock()
        fake.client.return_value.get_item.return_value = {"Item": {"status": {"S": "HEALTHY"}}}
        with mock.patch.dict(os.environ, {"STATE_TABLE": "demo"}), mock.patch.dict(sys.modules, {"boto3": fake}):
            result = module.handler({"rawPath": "/health"}, None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(json.loads(result["body"])["status"], "healthy")

    def test_failure_raises_for_cloudwatch_error_metric(self):
        module = load("demo_app_bad", "app.py")
        fake = mock.Mock()
        fake.client.return_value.get_item.return_value = {"Item": {"status": {"S": "FAILED"}}}
        with mock.patch.dict(os.environ, {"STATE_TABLE": "demo"}), mock.patch.dict(sys.modules, {"boto3": fake}):
            with self.assertRaises(RuntimeError):
                module.handler({"rawPath": "/health"}, None)

    def test_unrelated_alarm_is_ignored(self):
        module = load("demo_remediate", "remediate.py")
        with mock.patch.dict(os.environ, {"EXPECTED_ALARM": "expected"}):
            result = module.handler({"source": "aws.cloudwatch", "detail-type": "CloudWatch Alarm State Change",
                                     "detail": {"alarmName": "other", "state": {"value": "ALARM"}}}, None)
        self.assertEqual(result["result"], "ignored")

    def test_recovery_updates_state_and_notifies(self):
        module = load("demo_remediate_good", "remediate.py")
        fake = mock.Mock()
        with mock.patch.dict(os.environ, {"EXPECTED_ALARM": "expected", "STATE_TABLE": "demo", "SNS_TOPIC_ARN": "arn:demo"}), \
             mock.patch.dict(sys.modules, {"boto3": fake}):
            result = module.handler({"source": "aws.cloudwatch", "detail-type": "CloudWatch Alarm State Change",
                                     "detail": {"alarmName": "expected", "state": {"value": "ALARM"}}}, None)
        self.assertEqual(result["result"], "recovered")
        fake.client.return_value.update_item.assert_called_once()
        fake.client.return_value.publish.assert_called_once()

if __name__ == "__main__":
    unittest.main()
