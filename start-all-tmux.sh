#!/bin/bash
# Start a new tmux session to run the cluster status scripts.

SESSION=$USER-cluster-stats

cd /scratch/gvantulder/queue-stats/

tmux -2 new-session -d -s $SESSION

tmux new-window -t $SESSION:1 -n "Queue-stats"
tmux send-keys "/scratch/gvantulder/queue-stats/xml/run-update.sh" C-m

tmux new-window -t $SESSION:2 -n "Mem-stats"
tmux send-keys "./qstat-memory-logger.sh" C-m

tmux new-window -t $SESSION:3 -n "Accounting"
tmux send-keys "./run-accounting.sh" C-m

tmux new-window -t $SESSION:4 -n "Web"
tmux send-keys 'ruby server.rb -o "0.0.0.0" -p "18888"' C-m

