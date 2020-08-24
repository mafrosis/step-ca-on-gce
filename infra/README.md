Infra As Code
=============

## System Diagram

This component diagram shows the various things created by the terraform code herein:

```
┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 
  step-ca project                                  australia-southeast1  │
│                                                                         
       ┌──────────────────────────────────┐                              │
│      │ google_compute_instance (mig.tf) │   ┌───────────────────────┐   
       │ _group_manager                   │   │ google_storage_bucket │  │
│      │                            ┌─────┼──▶│ (storage.tf)          │   
       │  ┌───────────────────┐     │     │   │                       │  │
│      │  │ e2-micro (COS)    │     │     │   └───────────────────────┘   
       │  │                   │    fuse   │                              │
│      │  │  ┌─────────────┐  │    mount  │                               
       │  │  │  Container  │  │     │     │                              │
│    ┌─┼──┼─▶│             │──┼─────┘     │                               
     │ │  │  └─────────────┘  │           │                              │
│    │ │  └───────────────────┘           │                               
     │ │  ┌──────────┐ ┌──────┐           │                              │
│    │ │  │autoscaler│ │health│           │                               
     │ │  │          │ │_check│           │                              │
│    │ │  └──────────┘ └──────┘           │                               
     │ └──────────────────────────────────┘                              │
│    │                                                                    
   ┌─┼───────────────────────────────────────────────────┐               │
│  │ │                           Cloud Run (cloudrun.tf) │                
   │ │  ┌─────────────────┐                              │               │
│  │ │  │google_vpc_access│        ┌─────────────────┐   │                
   │ └──│   _connector    │◀──┐    │google_cloud_run_│   │               │
│  │    └─────────────────┘   └────│     service     │   │                
   │                               └─────────────────┘   │               │
│  └─────────────────────────────────────────────────────┘                
                                                                         │
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 
```

## How to Use

The `Makefile` has a couple of environment vars you will want to override:

 1. `PROJECT_ID` - The GCP project ID to use.
 2. `TF_STATE_BUCKET` - The GCS bucket where state should be stored.

There are a few assumptions made here about what is configured in the GCP project - the code used
to create the project [can be seen here](ihttps://github.com/mafrosis/gcp-bootstrap/tree/dev/projects/modules/gcp-project)
and [here](https://github.com/mafrosis/gcp-bootstrap/blob/dev/projects/step-ca/main.tf).

To actually run the code, simply:

    PROJECT_ID=proj123 TF_STATE_BUCKET=proj123_tf_state make init
    terraform apply


## SSH into GCE Helper

There is a convenience helper included in the `Makefile` to help SSH into the VM instance via IAP.
This relies on a [firewall rule](https://github.com/mafrosis/gcp-bootstrap/commit/ca7113cad512024d9aa1f1dcabb3cd99a70cedc4)
defined on the project's network:

    make ssh
