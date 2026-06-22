#!/usr/bin/env bash
# Run this inside the VM: sudo bash /vagrant/post-remediation-verification-commands.sh
# Output is captured to /vagrant/post-remediation-verification.txt

{
  echo "=== KijaniKiosk Post-Remediation Verification ==="
  echo "Timestamp: $(date -Is)"
  echo "Hostname:  $(hostname)"
  echo ""

  echo "--- [1] Force logrotate and check resulting file permissions ---"
  sudo logrotate --force /etc/logrotate.d/kijanikiosk 2>&1 || true
  echo ""

  echo "--- [2] Directory listing after rotation ---"
  ls -la /opt/kijanikiosk/shared/logs/
  echo ""

  echo "--- [3] ACL state on shared/logs after rotation ---"
  getfacl /opt/kijanikiosk/shared/logs/
  echo ""

  echo "--- [4] Definitive access model test: kk-api write after logrotate ---"
  sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp \
    && echo "PASS: kk-api can write after logrotate" \
    || echo "FAIL: kk-api cannot write to shared/logs"
  echo ""

  echo "--- [5] kk-payments read access after logrotate ---"
  sudo -u kk-payments ls /opt/kijanikiosk/shared/logs/ \
    && echo "PASS: kk-payments can read shared/logs" \
    || echo "FAIL: kk-payments read failed"
  echo ""

  echo "--- [6] Health check JSON readable by kijanikiosk group ---"
  cat /opt/kijanikiosk/health/last-provision.json
  echo ""
  ls -la /opt/kijanikiosk/health/last-provision.json
  echo ""

  echo "--- [7] logrotate --debug clean pass ---"
  sudo logrotate --debug /etc/logrotate.d/kijanikiosk 2>&1
  echo ""

  echo "--- [8] Service states ---"
  for unit in kk-api kk-payments kk-logs; do
    systemctl is-active "${unit}.service" && echo "ACTIVE: ${unit}" || echo "INACTIVE: ${unit}"
  done
  echo ""

  echo "--- [9] Hardening scores (final) ---"
  for unit in kk-api kk-logs kk-payments; do
    SCORE=$(systemd-analyze security "${unit}.service" 2>/dev/null | tail -1 | grep -oP '\d+\.\d+' || echo "N/A")
    echo "${unit}.service: $SCORE"
  done
  echo ""

  echo "--- [10] UFW final ruleset ---"
  sudo ufw status verbose
  echo ""

  echo "--- [11] nginx hold status ---"
  apt-mark showhold
  echo ""

  echo "--- [12] Journal persistence confirmation ---"
  ls -la /var/log/journal/
  journalctl --disk-usage

} | tee /vagrant/post-remediation-verification.txt
