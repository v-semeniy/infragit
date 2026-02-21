import boto3
import os
import json
from datetime import datetime

ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Lambda function to start/stop EC2 instances with tag backend-asg-instance
    Runs every 10 minutes with 2-minute delay between stop and start
    """
    
    # Get action from event
    action = event.get('action', 'stop')  # 'start' or 'stop'
    tag_key = 'Name'
    tag_value = 'backend-asg-instance'
    
    print(f"Action: {action}")
    print(f"Looking for instances with tag {tag_key}={tag_value}")
    
    try:
        # Find instances with specific tag
        response = ec2.describe_instances(
            Filters=[
                {
                    'Name': f'tag:{tag_key}',
                    'Values': [tag_value]
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running', 'stopped']
                }
            ]
        )
        
        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
                # Get instance name from tags
                instance_name = 'N/A'
                if 'Tags' in instance:
                    for tag in instance['Tags']:
                        if tag['Key'] == 'Name':
                            instance_name = tag['Value']
                            break
                print(f"Found instance: {instance['InstanceId']} ({instance_name}) - State: {instance['State']['Name']}")
        
        if not instance_ids:
            print(f"No instances found with tag {tag_key}={tag_value}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'No instances found with tag {tag_key}={tag_value}',
                    'timestamp': datetime.utcnow().isoformat()
                })
            }
        
        # Perform action
        if action == 'stop':
            # Stop ALL running instances
            running_instances = [
                inst['InstanceId'] 
                for reservation in response['Reservations'] 
                for inst in reservation['Instances'] 
                if inst['State']['Name'] == 'running'
            ]
            
            if running_instances:
                print(f"Stopping {len(running_instances)} instances: {running_instances}")
                ec2.stop_instances(InstanceIds=running_instances)
                message = f"Stopped {len(running_instances)} instances"
            else:
                message = "No running instances to stop"
                
        elif action == 'start':
            # Start ALL stopped instances
            stopped_instances = [
                inst['InstanceId'] 
                for reservation in response['Reservations'] 
                for inst in reservation['Instances'] 
                if inst['State']['Name'] == 'stopped'
            ]
            
            if stopped_instances:
                print(f"Starting {len(stopped_instances)} instances: {stopped_instances}")
                ec2.start_instances(InstanceIds=stopped_instances)
                message = f"Started {len(stopped_instances)} instances"
            else:
                message = "No stopped instances to start"
        else:
            raise ValueError(f"Invalid action: {action}")
        
        print(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': message,
                'total_instances': len(instance_ids),
                'action': action,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
