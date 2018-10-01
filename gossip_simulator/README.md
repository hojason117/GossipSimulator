# GossipSimulator

### Instructions:
```sh
cd gossip_simulator/
```

##### Sample Input
```sh
mix run lib/proj2.exs 1000 3D gossip
```

##### Sample Output
```sh
Assigning neighbors...
Start gossiping...
Progress: [  1%]
...
Progress: [100%]
All nodes propagated, convergence achieved.
Duration: 2 (sec)
```

### What is working
Topology: full, 3D, rand2D, torus, line, imp2D  
Algorithm: gossip, push-sum

### Largest network managed to deal with
##### Gossip:
full: 10000 (73 sec)  
3D: 30000 (10 sec)  
rand2D: 5000 (2 sec)  
torus: 30000 (21 sec)  
line: 1000 (72 sec)  
imp2D: 10000 (3 sec)
##### Push-sum:
full: 7500 (1330 sec)  
3D: 7500 (469 sec)  
rand2D: 3000 (266 sec)  
torus: 5000 (533 sec)  
line: 3000 (251 sec)  
imp2D: 7500 (146 sec)