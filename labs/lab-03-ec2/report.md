
# DSO303 – Lab 03 Report
## Amazon EC2 and Deploying the USMS Application

### 1. Introduction

This laboratory focused on deploying the University Student Management System (USMS) using Amazon EC2 within the VPC created in the previous laboratory. The lab combined resources from IAM and VPC, including the EC2 instance profile, public and private subnets, security groups, and routing configuration.

A two-tier architecture was implemented. The web tier was deployed in a public subnet, while the database tier was placed in a private subnet. The web server was configured using EC2 user data, assigned an Elastic IP, and provided with a separate EBS data volume. The lab also demonstrated IAM instance profiles, key-pair security, AMIs, instance persistence, and verification of the network and security configuration.

### 2. Objectives

The main objectives of this laboratory were:

- To understand the main components of an EC2 instance, including AMIs, instance types, and storage.
- To launch EC2 instances into specific public and private subnets.
- To configure EC2 instances with security groups and IAM instance profiles.
- To create and securely manage an EC2 key pair.
- To use user-data for automatic instance configuration.
- To understand the difference between auto-assigned public IP addresses and Elastic IP addresses.
- To create and attach an EBS volume.
- To implement a two-tier web and database architecture.
- To create an AMI from a configured EC2 instance.
- To verify that the deployed infrastructure persists after restarting the Floci environment.

### 3. Prerequisites and Previous Lab Integration

The laboratory depended on the resources created in Lab 01 and Lab 02. From Lab 01, the EC2 instance profile `usms-ec2-app-profile` and the associated `usms-ec2-app-role` were reused. From Lab 02, the VPC, public and private subnets, security groups, Internet Gateway, NAT Gateway, and route tables were reused.

The main network used the `10.0.0.0/16` VPC with the following subnet structure:

| Resource | CIDR | Availability Zone |
|---|---|---|
| Public Subnet A | `10.0.1.0/24` | `us-east-1a` |
| Public Subnet B | `10.0.2.0/24` | `us-east-1b` |
| Private Subnet A | `10.0.3.0/24` | `us-east-1a` |
| Private Subnet B | `10.0.4.0/24` | `us-east-1b` |

This demonstrated how resources from multiple AWS services and previous labs can be combined to create a complete cloud infrastructure.

### 4. Architecture

The final architecture consisted of two main tiers:

```text
                         Internet
                            |
                     Internet Gateway
                            |
                   Public Subnet A
                     10.0.1.0/24
                            |
                    usms-web-01
                     EC2 t3.micro
                            |
                    usms-app-sg
                            |
                     Elastic IP
                            |
                    ----------------
                            |
                    Private Subnet A
                     10.0.3.0/24
                            |
                     usms-db-01
                     EC2 t3.micro
                            |
                       usms-db-sg
                            |
                    PostgreSQL : 5432
````

The web instance was deployed in the public subnet and was accessible through a public address. The database instance was deployed in the private subnet and did not have a public address. The database security group allowed PostgreSQL traffic only from the web tier's security group.

### 5. Implementation

#### 5.1 Environment Preparation

The Floci environment was started using hybrid storage, and configuration files from the previous labs were loaded. These configuration files provided the required subnet, security group, instance profile, and Availability Zone information.

The existing Lab 02 network was verified before deploying EC2 resources. This confirmed that the VPC infrastructure required by Lab 03 was available and correctly configured.

#### 5.2 AMI Selection

An AMI was selected programmatically rather than using a hard-coded image ID. The lab emphasized that AMI IDs can differ between AWS regions and can change when new operating system images are released.

The lab also introduced the use of AWS Systems Manager public parameters as the preferred approach on real AWS for resolving the latest Amazon Linux AMI.

#### 5.3 EC2 Key Pair

An EC2 key pair named `usms-app-key` was created for the web application. The private key was stored in:

```text
outputs/usms-app-key.pem
```

The file permissions were restricted using `chmod 600`. The private key was also verified as Git-ignored to prevent accidental exposure or committing of sensitive credentials.

#### 5.4 User Data Configuration

A bootstrap script named `user-data.sh` was created for the USMS web server. The script was designed to run during the first boot of an EC2 instance.

The script performs the following tasks:

* Updates the system.
* Installs nginx.
* Retrieves instance metadata using IMDSv2.
* Obtains the instance ID, Availability Zone, and private IP address.
* Creates the USMS student portal page.
* Creates a `health.json` endpoint.
* Starts nginx automatically.

The script was checked for syntax errors and kept below the EC2 user-data size limitation.

#### 5.5 Launching the Web Server

The web instance was launched as `usms-web-01` with the following configuration:

| Configuration    | Value                  |
| ---------------- | ---------------------- |
| Instance Type    | `t3.micro`             |
| Subnet           | `usms-public-subnet-a` |
| Security Group   | `usms-app-sg`          |
| Key Pair         | `usms-app-key`         |
| Instance Profile | `usms-ec2-app-profile` |
| Tier             | Web                    |

The instance was launched using an EC2 `run-instances` request based on a JSON CLI skeleton.

#### 5.6 Instance Verification

After launch, the instance was verified using `describe-instances`. The important properties included its running state, subnet, Availability Zone, private IP address, public IP address, security group, instance profile, and key pair.

The expected configuration placed `usms-web-01` in `usms-public-subnet-a`, with a private address in the `10.0.1.0/24` range and a public address assigned through the public subnet configuration.

#### 5.7 IAM Permission Chain

The IAM permission chain was traced from the EC2 instance to the policy:

```text
EC2 Instance
     ↓
Instance Profile
     ↓
IAM Role
     ↓
USMSStudentDataReadWrite Policy
```

The policy provides permissions such as `s3:GetObject`, `s3:PutObject`, and `s3:ListBucket` for the intended USMS student-data resources.

An important concept demonstrated in this step was that an IAM policy can refer to a resource that does not yet exist. The policy is valid, but its permissions only become effective against that resource once it is created.

#### 5.8 User Data Verification

The user-data stored by EC2 was retrieved, decoded, and compared with the original local script.

The verification confirmed that what EC2 stored was byte-identical to the original user-data script. This provided stronger evidence than simply assuming that the user-data submission succeeded because the API call returned successfully.

#### 5.9 Elastic IP

An Elastic IP named `usms-web-eip` was allocated and associated with `usms-web-01`.

The Elastic IP provided a stable public address for the web server. Unlike an automatically assigned public IP, the Elastic IP remains associated with the AWS account and can be attached to another instance when required.

#### 5.10 Application Testing

The USMS application was tested through its public address. In the Floci environment, the HTTP request may fail because Floci models the EC2 API but does not boot a real operating system or execute nginx inside the simulated instance.

Therefore, the network configuration was verified instead. The checks confirmed:

1. The EC2 instance was running.
2. The subnet had a route to the Internet Gateway.
3. The Internet Gateway was attached to the VPC.
4. The security group allowed TCP port 80.
5. The instance had a public address.
6. The network ACL permitted the traffic.

The missing seventh component in Floci was the actual process listening on port 80, which would be available on real AWS after the operating system and nginx were booted.

#### 5.11 EBS Data Volume

An additional 8 GiB `gp3` EBS volume named `usms-web-data-vol` was created and attached to `usms-web-01`.

The volume was created in the same Availability Zone as the EC2 instance because EBS volumes can only be attached to instances within the same Availability Zone.

The data volume was configured independently from the root volume, allowing it to survive instance termination when `DeleteOnTermination` is set to `False`.

#### 5.12 Database Tier

A second EC2 instance named `usms-db-01` was launched in `usms-private-subnet-a`.

| Configuration        | Value                   |
| -------------------- | ----------------------- |
| Instance Type        | `t3.micro`              |
| Subnet               | `usms-private-subnet-a` |
| Security Group       | `usms-db-sg`            |
| Public IP            | None                    |
| IAM Instance Profile | None                    |
| Tier                 | Data                    |

The database instance deliberately did not receive an IAM instance profile because it did not require access to S3. This follows the principle of least privilege.

#### 5.13 Two-Tier Security Verification

The database security group was verified to allow PostgreSQL traffic on port `5432` only from the web server's security group.

```text
Internet
   |
   v
usms-web-01
usms-app-sg
   |
   | TCP 5432
   v
usms-db-01
usms-db-sg
```

The database subnet used the NAT Gateway for outbound connectivity but had no route directly to the Internet Gateway. Therefore, the database tier was not directly reachable from the public internet.

#### 5.14 Stop and Start Testing

The web server was stopped and started to observe the behaviour of its network addresses.

The private IP address remained associated with the instance, while the Elastic IP remained available for the instance after it was started again.

The exercise demonstrated why a stable Elastic IP is useful for services that require a consistent public address. The lab also noted that Floci may not reproduce every real AWS networking behaviour exactly.

#### 5.15 Persistence Verification

The Floci environment was restarted and the EC2 resources were checked again.

The persistence verification confirmed that the instances, subnet associations, security groups, EBS volumes, and Elastic IP resources remained available after restarting the emulator.

This demonstrated the importance of using persistent or hybrid storage when working with the Floci environment.

#### 5.16 Golden AMI

An AMI named `usms-web-golden` was created from the configured web server.

The purpose of the AMI was to capture an already configured version of the web server so that future instances can be launched from a prepared image rather than reinstalling and configuring everything from the beginning.

The golden AMI is also intended for use in a later Auto Scaling laboratory.

### 6. Verification

A dedicated verification script, `verify-lab-03.sh`, was created to check the main components of the laboratory.

The verification covered:

* Floci environment.
* VPC and subnet dependencies.
* EC2 key pair.
* Web instance configuration.
* IAM instance profile.
* User data.
* Public IP and Elastic IP.
* EBS data volume.
* Database instance.
* Database security configuration.
* Golden AMI.
* Resource tagging.
* Configuration files.
* JSON validity.
* Git security.

The expected successful result was:

```text
PASS=36  FAIL=0
```

The verification process checked not only whether resources existed, but also whether important security and configuration properties were correct, such as the database having no public address and the private key not being tracked by Git.

### 7. Results

The laboratory successfully established the intended EC2-based USMS architecture.

| Component               | Result                           |
| ----------------------- | -------------------------------- |
| Web EC2 instance        | `usms-web-01`                    |
| Web subnet              | Public subnet A                  |
| Web security group      | `usms-app-sg`                    |
| Web IAM profile         | `usms-ec2-app-profile`           |
| Elastic IP              | `usms-web-eip`                   |
| Data volume             | `usms-web-data-vol`              |
| Database EC2 instance   | `usms-db-01`                     |
| Database subnet         | Private subnet A                 |
| Database security group | `usms-db-sg`                     |
| Database public IP      | None                             |
| Golden AMI              | `usms-web-golden`                |
| Private key             | Git-ignored and permission `600` |
| Verification            | `PASS=36 FAIL=0` expected        |

The laboratory therefore demonstrated the deployment of a complete two-tier compute architecture using EC2, EBS, IAM, VPC networking, security groups, and Elastic IP.

### 8. Floci Limitations

An important part of this laboratory was understanding the difference between the Floci emulator and real AWS.

Floci models many EC2 API-level resources, including instances, states, tags, volumes, key pairs, Elastic IP relationships, and user-data storage. However, it does not boot a real operating system inside every simulated EC2 instance.

Therefore, the following behaviours could not be fully observed in Floci:

* Actual operating system boot.
* Execution of cloud-init and user-data.
* nginx running inside the instance.
* Instance Metadata Service credentials.
* Actual security-group packet enforcement.
* SSH access.
* Real internet routing to the Elastic IP.
* Real CPU and memory behaviour.

These limitations were considered when interpreting the application connectivity tests.

### 9. What I Learned

From this laboratory, I understood how EC2 fits together with the networking and IAM resources created in the previous laboratories. The most important concept was that an EC2 instance is not an isolated resource. Its functionality depends on the AMI, subnet, route table, security group, IAM instance profile, storage, and public addressing configuration.

I also learned the importance of verifying infrastructure instead of simply trusting that a command succeeded. The user-data verification, two-tier security verification, and persistence test provided evidence that the configuration was actually stored and connected as intended.

The laboratory also improved my understanding of the difference between an automatically assigned public IP and an Elastic IP, as well as the importance of placing database resources in private subnets and restricting database access to the application tier.

### 10. Conclusion

This laboratory successfully demonstrated the deployment of the USMS application using Amazon EC2 in a two-tier architecture. The web server was deployed in a public subnet with an IAM instance profile, security group, user-data bootstrap script, Elastic IP, and additional EBS storage. A separate database-tier instance was deployed in a private subnet with restricted access from the web tier.

The laboratory also demonstrated secure key management, IAM role-based access, persistent storage, AMI creation, infrastructure verification, and resource persistence. Although Floci cannot simulate every behaviour of real AWS, it provided a useful environment for understanding EC2 resource relationships and cloud infrastructure configuration. Overall, the lab provided a strong foundation for the next stages of the USMS cloud deployment.

`
