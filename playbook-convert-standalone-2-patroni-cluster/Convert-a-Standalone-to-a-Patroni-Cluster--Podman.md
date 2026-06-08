# Instructions for Augment

Podman network to use -> lab-network 172.18.0.0/16

172.18.0.9      podpg-cls1-reader
172.18.0.10     podpg-cls1-writer
172.18.0.11     podpg-cls1-pg1
172.18.0.12     podpg-cls1-pg2
172.18.0.13     podpg-cls1-pg3
172.18.0.14     podpg-cls1-pg4
172.18.0.15     podpg-cls1-pg5
172.18.0.16     podpg-cls1-pg6

172.18.0.19     podpg-cls2-reader
172.18.0.20     podpg-cls2-writer
172.18.0.21     podpg-cls2-pg1
172.18.0.22     podpg-cls2-pg2
172.18.0.23     podpg-cls2-pg3
172.18.0.24     podpg-cls2-pg4
172.18.0.25     podpg-cls2-pg5
172.18.0.26     podpg-cls2-pg6

Similar to Convert-a-Standalone-to-a-Patroni-Cluster--RHEL.md, give me step by step commands to first setup a standalone postgresql 18 on 172.18.0.21.and podman-based-postgresql-cluster.md, provide me commands 