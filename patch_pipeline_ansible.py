import os

path = '/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/.github/workflows/pipeline.yml'
with open(path, 'r') as f:
    content = f.read()

# Update the "Run Ansible deploy playbook" step to run directly instead of through deploy.sh
target_step = '''      - name: Run Ansible deploy playbook
        working-directory: xworkmate-bridge
        env:
          INTERNAL_SERVICE_TOKEN: ${{ env.INTERNAL_SERVICE_TOKEN }}
          GHCR_USERNAME: ${{ env.GHCR_USERNAME }}
          GHCR_PASSWORD: ${{ env.GHCR_PASSWORD }}
          XWORKMATE_BRIDGE_IMAGE_ARTIFACT_PATH: ${{ github.workspace }}/xworkmate-bridge/dist/image-artifact/service-image-ref.txt
        run: bash ./scripts/github-actions/deploy.sh "${{ steps.deploy_meta.outputs.target_host }}" "${{ steps.deploy_meta.outputs.run_apply }}" ../playbooks'''

replacement_step = '''      - name: Run Ansible deploy playbook
        working-directory: playbooks
        env:
          ANSIBLE_CONFIG: ./ansible.cfg
          BRIDGE_AUTH_TOKEN: ${{ env.INTERNAL_SERVICE_TOKEN }}
        run: |
          SERVICE_COMPOSE_IMAGE="$(cat ../xworkmate-bridge/dist/image-artifact/service-image-ref.txt | xargs)"
          CHECK_MODE_FLAG=""
          if [[ "${{ steps.deploy_meta.outputs.run_apply }}" != "true" ]]; then
            CHECK_MODE_FLAG="-C"
          fi
          ansible-playbook -i inventory.ini deploy_xworkmate_bridge_vhosts.yml \\
            -D ${CHECK_MODE_FLAG} \\
            -l "${{ steps.deploy_meta.outputs.target_host }}" \\
            -e "service_compose_image=${SERVICE_COMPOSE_IMAGE}" \\
            -e "ghcr_username=${{ env.GHCR_USERNAME }}" \\
            -e "ghcr_password=${{ env.GHCR_PASSWORD }}"'''

content = content.replace(target_step, replacement_step)

with open(path, 'w') as f:
    f.write(content)
