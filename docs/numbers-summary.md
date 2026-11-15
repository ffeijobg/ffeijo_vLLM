# Numbers to remember (lab values: one 4 GB GPU, one replica)

| What | Number |
| --- | --- |
| Cold start to Ready | about 70 s |
| Pod kill to serving again | 64 s |
| Host reboot to vLLM Ready | 3 m 33 s |
| NFS stopped, then pod restart | 5 m 05 s outage |
| Kubelet stopped on the GPU node | node Unknown after 53 s, outage 2 m 43 s, 12 s to recover |
| Bad release: commit to abort (blue-green gate) | 4 m 38 s, 63 s from green appearing; 0 user-visible errors |
| Good release: commit to promoted | about 5 m 14 s (approximate) |
| Alert detection, vLLM down | stale 2 m 16 s, burn-rate 4 m 46 s (pending) |
| Alert detection, prober gone | stale 40 s, burn-rate silent |
| Idle p95 TTFT / inter-token | 0.058 s / 0.024 s |
| GPU memory | 0.80 budget about 2.9 GiB; 0.40 budget about 1.3 GiB per pod; two pods peaked at 2678 MiB of 4094 MiB |
| SLO | 99.5% over 28 days, budget about 201 min, fast burn 14.4x (7.2% error ratio) |
| Load-test knee | TODO (step 6.8) |
