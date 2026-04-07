#!/usr/bin/env python3
"""
benchmark_ddp.py — Distributed training smoke test for the gpu-stack ML validation.

Runs a minimal LLaMA-style transformer for a fixed number of steps using
torch.distributed (DDP) and reports tokens/sec. Used by the stack_validate
Ansible role ML smoke test (L1 validation).

Usage (via torchrun, launched by gpu-run in a PBS job):
    torchrun --nproc_per_node=<gpus_per_node> \\
             --nnodes=<node_count> \\
             --rdzv_backend=c10d \\
             --rdzv_endpoint=<master_addr>:<master_port> \\
             benchmark_ddp.py --model llama-1b --steps 50

Output:
    Writes one line per step to stdout:
        step <N>: <tokens_per_sec> tokens/sec
    Final line:
        RESULT tokens/sec=<value>

Exit code 0 on success, 1 on failure.
"""

import argparse
import os
import time

import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP


# ---------------------------------------------------------------------------
# Minimal LLaMA-style model definition
# ---------------------------------------------------------------------------

class RMSNorm(torch.nn.Module):
    def __init__(self, dim: int, eps: float = 1e-6):
        super().__init__()
        self.eps = eps
        self.weight = torch.nn.Parameter(torch.ones(dim))

    def forward(self, x):
        norm = x.pow(2).mean(-1, keepdim=True).add(self.eps).rsqrt()
        return x * norm * self.weight


class FeedForward(torch.nn.Module):
    def __init__(self, dim: int, hidden_dim: int):
        super().__init__()
        self.w1 = torch.nn.Linear(dim, hidden_dim, bias=False)
        self.w2 = torch.nn.Linear(hidden_dim, dim, bias=False)
        self.w3 = torch.nn.Linear(dim, hidden_dim, bias=False)

    def forward(self, x):
        return self.w2(torch.nn.functional.silu(self.w1(x)) * self.w3(x))


class TransformerBlock(torch.nn.Module):
    def __init__(self, dim: int, n_heads: int, hidden_dim: int):
        super().__init__()
        self.attn = torch.nn.MultiheadAttention(dim, n_heads, batch_first=True)
        self.ff = FeedForward(dim, hidden_dim)
        self.norm1 = RMSNorm(dim)
        self.norm2 = RMSNorm(dim)

    def forward(self, x):
        x = x + self.attn(self.norm1(x), self.norm1(x), self.norm1(x))[0]
        x = x + self.ff(self.norm2(x))
        return x


MODEL_CONFIGS = {
    "llama-1b": dict(dim=2048, n_layers=16, n_heads=16, hidden_dim=5504, vocab_size=32000),
    "llama-7b": dict(dim=4096, n_layers=32, n_heads=32, hidden_dim=11008, vocab_size=32000),
}


def build_model(config: dict) -> torch.nn.Module:
    layers = torch.nn.ModuleList([
        TransformerBlock(config["dim"], config["n_heads"], config["hidden_dim"])
        for _ in range(config["n_layers"])
    ])
    return torch.nn.Sequential(
        torch.nn.Embedding(config["vocab_size"], config["dim"]),
        *layers,
        torch.nn.Linear(config["dim"], config["vocab_size"], bias=False),
    )


# ---------------------------------------------------------------------------
# Training loop
# ---------------------------------------------------------------------------

def run(args):
    dist.init_process_group("nccl")
    rank = dist.get_rank()
    local_rank = int(os.environ.get("LOCAL_RANK", rank))

    device = torch.device(f"cuda:{local_rank}")
    torch.cuda.set_device(device)

    cfg = MODEL_CONFIGS[args.model]
    model = build_model(cfg).to(device)
    model = DDP(model, device_ids=[local_rank])

    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-4)

    batch_size = args.batch_size
    seq_len = args.seq_len
    vocab_size = cfg["vocab_size"]

    tokens_per_step = batch_size * seq_len * dist.get_world_size()
    total_tokens = 0
    t_start = time.perf_counter()

    for step in range(1, args.steps + 1):
        x = torch.randint(0, vocab_size, (batch_size, seq_len), device=device)
        y = torch.randint(0, vocab_size, (batch_size, seq_len), device=device)

        t0 = time.perf_counter()
        logits = model(x)
        loss = torch.nn.functional.cross_entropy(
            logits.view(-1, vocab_size), y.view(-1)
        )
        loss.backward()
        optimizer.step()
        optimizer.zero_grad()
        torch.cuda.synchronize()
        dt = time.perf_counter() - t0

        total_tokens += tokens_per_step
        tps = tokens_per_step / dt

        if rank == 0:
            print(f"step {step}: {tps:.0f} tokens/sec", flush=True)

    elapsed = time.perf_counter() - t_start
    avg_tps = total_tokens / elapsed

    if rank == 0:
        print(f"RESULT tokens/sec={avg_tps:.0f}", flush=True)

    dist.destroy_process_group()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DDP smoke test for gpu-stack validation")
    parser.add_argument("--model",      default="llama-1b", choices=list(MODEL_CONFIGS))
    parser.add_argument("--steps",      type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--seq-len",    type=int, default=512)
    args = parser.parse_args()

    run(args)
