#!/usr/bin/env bash
set -euo pipefail

VPC_ID="${1:-}"
REGION="${2:-us-east-1}"

if [[ -z "$VPC_ID" ]]; then
  echo "Usage: $0 <vpc-id> [region]"
  exit 1
fi

awsr() {
  aws --region "$REGION" "$@"
}

has_values() {
  local v="${1:-}"
  [[ -n "$v" && "$v" != "None" && "$v" != "null" ]]
}

echo "==> Target VPC: $VPC_ID (region: $REGION)"

echo "==> Deleting EKS clusters in this VPC (if any)"
clusters="$(awsr eks list-clusters --query 'clusters[]' --output text 2>/dev/null || true)"
if has_values "$clusters"; then
  for cluster in $clusters; do
    cluster_vpc="$(awsr eks describe-cluster --name "$cluster" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true)"
    if [[ "$cluster_vpc" == "$VPC_ID" ]]; then
      echo "  - EKS cluster: $cluster"
      nodegroups="$(awsr eks list-nodegroups --cluster-name "$cluster" --query 'nodegroups[]' --output text 2>/dev/null || true)"
      if has_values "$nodegroups"; then
        for ng in $nodegroups; do
          echo "    - deleting nodegroup: $ng"
          awsr eks delete-nodegroup --cluster-name "$cluster" --nodegroup-name "$ng" >/dev/null 2>&1 || true
          awsr eks wait nodegroup-deleted --cluster-name "$cluster" --nodegroup-name "$ng" >/dev/null 2>&1 || true
        done
      fi

      fargates="$(awsr eks list-fargate-profiles --cluster-name "$cluster" --query 'fargateProfileNames[]' --output text 2>/dev/null || true)"
      if has_values "$fargates"; then
        for fp in $fargates; do
          echo "    - deleting fargate profile: $fp"
          awsr eks delete-fargate-profile --cluster-name "$cluster" --fargate-profile-name "$fp" >/dev/null 2>&1 || true
        done
      fi

      awsr eks delete-cluster --name "$cluster" >/dev/null 2>&1 || true
      awsr eks wait cluster-deleted --name "$cluster" >/dev/null 2>&1 || true
    fi
  done
fi

echo "==> Deleting load balancers in this VPC"
alb_arns="$(awsr elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true)"
if has_values "$alb_arns"; then
  for arn in $alb_arns; do
    echo "  - deleting ALB/NLB: $arn"
    awsr elbv2 delete-load-balancer --load-balancer-arn "$arn" >/dev/null 2>&1 || true
  done
  sleep 20
fi

clb_names="$(awsr elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" --output text 2>/dev/null || true)"
if has_values "$clb_names"; then
  for name in $clb_names; do
    echo "  - deleting Classic ELB: $name"
    awsr elb delete-load-balancer --load-balancer-name "$name" >/dev/null 2>&1 || true
  done
fi

echo "==> Terminating EC2 instances in this VPC"
instance_ids="$(awsr ec2 describe-instances \
  --filters Name=vpc-id,Values="$VPC_ID" Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)"
if has_values "$instance_ids"; then
  echo "  - instances: $instance_ids"
  awsr ec2 terminate-instances --instance-ids $instance_ids >/dev/null 2>&1 || true
  awsr ec2 wait instance-terminated --instance-ids $instance_ids >/dev/null 2>&1 || true
fi

echo "==> Deleting NAT gateways"
nat_ids="$(awsr ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC_ID" --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || true)"
if has_values "$nat_ids"; then
  for nat in $nat_ids; do
    echo "  - deleting NAT GW: $nat"
    awsr ec2 delete-nat-gateway --nat-gateway-id "$nat" >/dev/null 2>&1 || true
    awsr ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat" >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting VPC endpoints"
vpce_ids="$(awsr ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$VPC_ID" --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || true)"
if has_values "$vpce_ids"; then
  echo "  - endpoints: $vpce_ids"
  awsr ec2 delete-vpc-endpoints --vpc-endpoint-ids $vpce_ids >/dev/null 2>&1 || true
fi

echo "==> Deleting transit-gateway attachments to this VPC"
tgw_attach_ids="$(awsr ec2 describe-transit-gateway-vpc-attachments --filters Name=resource-id,Values="$VPC_ID" --query 'TransitGatewayVpcAttachments[].TransitGatewayAttachmentId' --output text 2>/dev/null || true)"
if has_values "$tgw_attach_ids"; then
  for a in $tgw_attach_ids; do
    echo "  - deleting TGW attachment: $a"
    awsr ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id "$a" >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting non-main route tables"
rtb_ids="$(awsr ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC_ID" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null || true)"
if has_values "$rtb_ids"; then
  for rtb in $rtb_ids; do
    is_main="$(awsr ec2 describe-route-tables --route-table-ids "$rtb" --query 'length(RouteTables[0].Associations[?Main==`true`])' --output text 2>/dev/null || echo 0)"
    if [[ "$is_main" == "0" ]]; then
      assoc_ids="$(awsr ec2 describe-route-tables --route-table-ids "$rtb" --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' --output text 2>/dev/null || true)"
      if has_values "$assoc_ids"; then
        for assoc in $assoc_ids; do
          awsr ec2 disassociate-route-table --association-id "$assoc" >/dev/null 2>&1 || true
        done
      fi
      echo "  - deleting route table: $rtb"
      awsr ec2 delete-route-table --route-table-id "$rtb" >/dev/null 2>&1 || true
    fi
  done
fi

echo "==> Deleting internet gateways attached to this VPC"
igw_ids="$(awsr ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || true)"
if has_values "$igw_ids"; then
  for igw in $igw_ids; do
    echo "  - detaching/deleting IGW: $igw"
    awsr ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" >/dev/null 2>&1 || true
    awsr ec2 delete-internet-gateway --internet-gateway-id "$igw" >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting subnets"
subnet_ids="$(awsr ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)"
if has_values "$subnet_ids"; then
  for subnet in $subnet_ids; do
    echo "  - deleting subnet: $subnet"
    awsr ec2 delete-subnet --subnet-id "$subnet" >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting non-default network ACLs"
nacl_ids="$(awsr ec2 describe-network-acls --filters Name=vpc-id,Values="$VPC_ID" --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text 2>/dev/null || true)"
if has_values "$nacl_ids"; then
  for nacl in $nacl_ids; do
    echo "  - deleting NACL: $nacl"
    awsr ec2 delete-network-acl --network-acl-id "$nacl" >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting non-default security groups"
sg_ids="$(awsr ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || true)"
if has_values "$sg_ids"; then
  for sg in $sg_ids; do
    echo "  - deleting SG: $sg"
    awsr ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting available ENIs"
eni_ids="$(awsr ec2 describe-network-interfaces --filters Name=vpc-id,Values="$VPC_ID" Name=status,Values=available --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true)"
if has_values "$eni_ids"; then
  for eni in $eni_ids; do
    echo "  - deleting ENI: $eni"
    awsr ec2 delete-network-interface --network-interface-id "$eni" >/dev/null 2>&1 || true
  done
fi

echo "==> Final attempt: delete VPC"
if awsr ec2 delete-vpc --vpc-id "$VPC_ID" >/tmp/delete-vpc-result.json 2>/tmp/delete-vpc-error.txt; then
  echo "SUCCESS: VPC deleted: $VPC_ID"
  exit 0
fi

echo "FAILED: VPC still has dependencies."
echo "AWS error:"
cat /tmp/delete-vpc-error.txt
exit 2
