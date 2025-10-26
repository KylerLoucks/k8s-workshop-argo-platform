resource "null_resource" "k3d_cluster" {
  for_each = toset(var.cluster_names)

  triggers = {
    cluster  = each.key
    expose   = tostring(var.expose_lb)
    lb_ports = join(",", var.lb_ports)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<EOT
set -e
NAME='${each.key}'
K3D='${var.k3d_binary}'
if ! $K3D kubeconfig get "$NAME" >/dev/null 2>&1; then
  FLAGS=""
  if [ "${var.expose_lb}" = "true" ]; then
    for p in ${join(" ", var.lb_ports)}; do FLAGS="$FLAGS -p $p"; done
  fi
  echo "[create] k3d cluster $NAME $FLAGS"
  $K3D cluster create "$NAME" $FLAGS --wait
else
  echo "[skip] cluster $NAME already exists"
fi
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-lc"]
    command     = <<EOT
set -e
NAME='${each.key}'
${var.k3d_binary} cluster delete "$NAME" || true
EOT
  }
}
