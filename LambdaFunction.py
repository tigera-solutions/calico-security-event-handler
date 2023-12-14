import os, re, base64, json
import boto3
from aws_lambda_powertools import Logger
from botocore.signers import RequestSigner
from kubernetes import client, config

logger = Logger()

def get_session():
    return boto3.session.Session()

def get_cluster_info(cluster_name):
    eks = boto3.client('eks')
    try:
        cluster_info = eks.describe_cluster(name=cluster_name)['cluster']
        return {
            "endpoint": cluster_info['endpoint'],
            "ca": cluster_info['certificateAuthority']['data']
        }
    except Exception as e:
        logger.error(f"Error getting cluster info for {cluster_name}: {e}")
        raise

def get_bearer_token(cluster_name, session):
    service_id = session.client('sts').meta.service_model.service_id
    signer = RequestSigner(
        service_id,
        session.region_name,
        'sts',
        'v4',
        session.get_credentials(),
        session.events
    )

    try:
        signed_url = signer.generate_presigned_url({
            'method': 'GET',
            'url': f'https://sts.{session.region_name}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15',
            'body': {},
            'headers': {'x-k8s-aws-id': cluster_name},
            'context': {}
        }, region_name=session.region_name, expires_in=60, operation_name='')

        return 'k8s-aws-v1.' + re.sub(r'=*', '', base64.urlsafe_b64encode(signed_url.encode('utf-8')).decode('utf-8'))
    except Exception as e:
        logger.error(f"Error generating bearer token for {cluster_name}: {e}")
        raise

def label_namespace(v1_api, namespace_name, label_key, label_value):
    body = {
        "metadata": {
            "labels": {
                label_key: label_value
            }
        }
    }

    try:
        api_response = v1_api.patch_namespace(namespace_name, body)
        logger.info(f"Labeled namespace '{namespace_name}' with '{label_key}={label_value}'. Response: {api_response}")
    except Exception as e:
        logger.error(f"Error labeling namespace '{namespace_name}': {e}")
        raise

def label_specific_pod(v1_api, namespace_name, pod_name, label_key, label_value):
    try:
        body = {
            "metadata": {
                "labels": {
                    label_key: label_value
                }
            }
        }

        api_response = v1_api.patch_namespaced_pod(name=pod_name, namespace=namespace_name, body=body)
        logger.info(f"Labeled pod '{pod_name}' in namespace '{namespace_name}' with '{label_key}={label_value}'. Response: {api_response}")
    except Exception as e:
        logger.error(f"Error labeling pod '{pod_name}' in namespace '{namespace_name}': {e}")
        raise

def create_packet_capture(custom_objects_api, namespace, packet_capture_name, selector, start_time=None, end_time=None, filters=None):
    try:
        # Check if the PacketCapture already exists
        existing = custom_objects_api.get_namespaced_custom_object(
            group="projectcalico.org",
            version="v3",
            namespace=namespace,
            plural="packetcaptures",
            name=packet_capture_name
        )
        logger.info(f"PacketCapture '{packet_capture_name}' already exists in namespace '{namespace}'. Skipping creation.")
        return existing
    except Exception as e:
        if e.status != 404:  # If the error is not a 'Not Found' error
            logger.error(f"Error checking for existing PacketCapture '{packet_capture_name}' in namespace '{namespace}': {e}")
            raise

    packet_capture_body = {
        "apiVersion": "projectcalico.org/v3",
        "kind": "PacketCapture",
        "metadata": {
            "name": packet_capture_name,
            "namespace": namespace
        },
        "spec": {
            "selector": selector
        }
    }

    if start_time:
        packet_capture_body["spec"]["startTime"] = start_time
    if end_time:
        packet_capture_body["spec"]["endTime"] = end_time
    if filters:
        packet_capture_body["spec"]["filters"] = filters

    try:
        api_response = custom_objects_api.create_namespaced_custom_object(
            group="projectcalico.org",
            version="v3",
            namespace=namespace,
            plural="packetcaptures",
            body=packet_capture_body
        )
        logger.info(f"PacketCapture '{packet_capture_name}' created in namespace '{namespace}'. Response: {api_response}")
    except Exception as e:
        logger.error(f"Error creating PacketCapture '{packet_capture_name}' in namespace '{namespace}': {e}")
        raise

def lambda_handler(event, context):
    cluster_name = "demo"
    session = get_session()
    cluster = get_cluster_info(cluster_name)
    
    kubeconfig = {
        'apiVersion': 'v1',
        'clusters': [{'name': 'cluster', 'cluster': {'certificate-authority-data': cluster["ca"], 'server': cluster["endpoint"]}}],
        'contexts': [{'name': 'lambda', 'context': {'cluster': 'cluster', "user": "lambda"}}],
        'current-context': 'lambda',
        'kind': 'Config',
        'preferences': {},
        'users': [{'name': 'lambda', "user": {'token': get_bearer_token(cluster_name, session)}}]
    }

    config.load_kube_config_from_dict(config_dict=kubeconfig)
    v1_api = client.CoreV1Api()
    custom_objects_api = client.CustomObjectsApi()

    logger.info(f"Received event: {json.dumps(event)}")

    detail = event.get('detail', {})
    if detail.get('mitre_tactic') == 'Initial Access':
        record = detail.get('record', {})
        source_info = {"source_ip": record.get('source', {}).get('ip'), "source_name": record.get('source', {}).get('name'), "source_namespace": record.get('source', {}).get('namespace')}
        logger.info(f"Source Information: {source_info}")

        namespace_to_label = "attack"
        label_namespace(v1_api, namespace_to_label, "quarantine", "true")

        pod_to_label = "attack"
        label_specific_pod(v1_api, namespace_to_label, pod_to_label, "quarantine", "true")

        packet_capture_name = "collect-evidence"
        create_packet_capture(custom_objects_api, namespace_to_label, packet_capture_name, "all()")
    
    return {'statusCode': 200, 'body': json.dumps('Event processed successfully.')}

if __name__ == "__main__":
    print(lambda_handler(None, None))

