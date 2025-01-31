# Demo Overview

Prometheus metrics to check:

```
container_memory_usage_bytes{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}
container_cpu_usage_seconds_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}
container_cpu_cfs_periods_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}
max(rate(container_cpu_usage_seconds_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}[5m])) by (pod) * 100


# CPU usage across all cores (should show higher values)
sum(rate(container_cpu_usage_seconds_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}[5m])) * 100

# Memory usage in GB
container_memory_usage_bytes{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"} / 1024 / 1024 / 1024
```

Sample spec with node_selector and toleration for gpu-slice:
```yaml
...
spec {
        node_selector = {
          "tier" = "gpu-slice"
        }
        toleration {
          key      = "nvidia.com/gpu"
          operator = "Equal"
          value    = "present"
          effect   = "NoSchedule"
        }
        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }
        container {
          name              = "dev"
          image             = "trquacker/coder_cuda"
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
          }
...
```


This part of the demo is a jupyter notebook that demonstrates how to train a random forest classifier on a large synthetic dataset while monitoring the CPU usage.

### First cell - imports
```python
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
import matplotlib.pyplot as plt
import psutil
import time
from IPython.display import clear_output
import threading
import gc

def plot_cpu_usage(cpu_history, time_history):
    plt.figure(figsize=(10, 6))
    plt.plot(time_history, cpu_history)
    plt.xlabel('Time (seconds)')
    plt.ylabel('CPU Usage (100% = 1 core)')
    plt.title('CPU Usage Over Time')
    plt.grid(True)
    # Add a horizontal line at 100% to show 1 core threshold
    plt.axhline(y=100, color='r', linestyle='--', label='1 Core')
    plt.axhline(y=200, color='g', linestyle='--', label='2 Cores')
    plt.axhline(y=300, color='y', linestyle='--', label='3 Cores')
    plt.axhline(y=400, color='purple', linestyle='--', label='4 Cores')
    plt.legend()
    plt.show()
```

### Second cell - Generate a large synthetic dataset
```python
# Reduced dataset size and features
n_samples = 50000  # Reduced from 100000
n_features = 50    # Reduced from 100

print("Generating large dataset...")
X = np.random.randn(n_samples, n_features)
y = np.random.randint(0, 2, n_samples)  # Binary classification

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)
print(f"Training data shape: {X_train.shape}")

# Reduced repetition
X_train = np.repeat(X_train, 2, axis=0)  # Changed from 3 to 2
y_train = np.repeat(y_train, 2, axis=0)  # Changed from 3 to 2
```

### Third cell - Training with CPU monitoring
```python
# Configure model to push CPU harder
rf_model = RandomForestClassifier(
    n_estimators=100,    # Increased from 50
    max_depth=None,      
    min_samples_split=2,
    n_jobs=4,           
    bootstrap=True,
    max_features='all',  # Changed from 'sqrt' to use all features
    verbose=1           
)

# Clear any cached data
gc.collect()

cpu_history = []
time_history = []
start_time = time.time()

def get_cpu_percent():
    # Get per-CPU utilization and sum them (can go up to 400% for 4 cores)
    return sum(psutil.cpu_percent(interval=0.05, percpu=True))

print("Starting model training...")
monitor_thread = threading.Thread(target=rf_model.fit, args=(X_train, y_train))
monitor_thread.start()

# Monitor with shorter intervals for more responsive updates
while monitor_thread.is_alive():
    current_time = time.time() - start_time
    cpu_percent = get_cpu_percent()  # This can now go up to 400% for 4 cores
    
    cpu_history.append(cpu_percent)
    time_history.append(current_time)
    
    clear_output(wait=True)
    plot_cpu_usage(cpu_history, time_history)
    time.sleep(0.1)  # Shorter sleep for more frequent updates

monitor_thread.join()
total_time = time_history[-1]
minutes = int(total_time // 60)
seconds = int(total_time % 60)
print("\nTraining completed!")
print(f"Total training time: {minutes}m {seconds}s")
```

### Running the notebook

If running from cursor or vscode, you need to activate the virtual environment.

```bash
source venv/bin/activate
```
