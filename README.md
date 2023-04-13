[![Build Status](https://github.com/atgreen/simple-scaler/actions/workflows/build.yml/badge.svg)](https://github.com/atgreen/simple-nodeport-service/actions)

# simple-nodeport-service

Simple-nodeport-service is an experiment.

Configuration
-------------

simple-nodeport-service expects to find a kubeconfig file at `/etc/simple-nodeport-service/kubeconfig`.

simple-nodeport-service is customized through a [TOML](https://toml.io)
formatted configuration file, `/etc/simple-nodeport-service/config.ini`.

| Setting         | Description                                            |
|-----------------+--------------------------------------------------------|
| `server-port`   | The port this service will listen to                   |
| `min-port`      | The minimum port number in the range of nodeport ports |
| `max-port`      | The maximum port number in the range of nodeport ports |

simple-nodeport-service runs on top of an embedded [etcd](https://etcd.io/)
database that runs as an asynchronous child process to simple-nodeport-service
(see [cl-etcd](https://github.com/atgreen/cl-etcd)).  Resilience is
maintained by load-balancing multiple instances of simple-nodeport-service, and
clustering the underlying `etcd` service.  This cluster of one, three
or five nodes, is configured in the `[etcd]` section of
`/etc/simple-nodeport-service/config.ini`.

| Setting                       | Description                                    |
|-------------------------------|------------------------------------------------  |
| `name`                        | The name of this etcd node                     |
| `debug-trace`                 | Any value enables logging of all etcd messages |
| `data-dir`                    | Path to persistent storage                     |
| `initial-advertise-peer-urls` | See etcd documentation                         |
| `listen-peer-urls`            | See etcd documentation                         |
| `listen-client-urls`          | See etcd documentation                         |
| `advertise-client-urls`       | See etcd documentation                         |
| `initial-cluster`             | See etcd documentation                         |

`simple-nodeport-service` is designed to run in kubernetes-managed containers.
Be sure to create persistent volumes for `data-dir`, otherwise etcd
nodes will not be able to rejoin the cluster if they are ever
restarted.  A good location for this might be
`/var/lib/simple-nodeport-service`.  See the example k8s yaml files in the `k8s`
directory for details.

Author & License
=================

simple-nodeport-service is an experiment by [Anthony
Green](https://linkedin.com/in/green), and is licensed under the terms
of the GNU Affero General Public License.  See the file COPYING for
details.
