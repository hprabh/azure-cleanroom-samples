# pylint: disable=line-too-long,too-many-statements,too-many-lines
# pylint: disable=too-many-return-statements
# pylint: disable=too-many-locals
# pylint: disable=protected-access
# pylint: disable=broad-except
# pylint: disable=too-many-branches
# pylint: disable=missing-timeout
# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring

# Note (gsinha): Various imports are also mentioned inline in the code at the point of usage.
# This is done to speed up command execution as having all the imports listed at top level is making
# execution slow for every command even if the top level imported packaged will not be used by that
# command.
import hashlib
import json
from multiprocessing import Value
import os
from time import sleep
import base64
from urllib.parse import urlparse
import uuid
import shlex
import jsonschema_specifications
from knack import CLI
from knack.log import get_logger
from azure.cli.core.util import CLIError
import oras.oci
import requests
import yaml
from azure.cli.core import get_default_cli

logger = get_logger(__name__)


def az_cli(args_str: str):
    args = args_str.split()
    cli = get_default_cli()
    out_file = open(os.devnull, "w")
    try:
        cli.invoke(args, out_file=out_file)
    except SystemExit:
        pass
    except:
        logger.warning(f"Command failed: {args}")
        raise

    if cli.result.result:
        return cli.result.result
    elif cli.result.error:
        if isinstance(cli.result.error, SystemExit):
            if cli.result.error.code == 0:
                return True
        logger.warning(f"Command failed: {args}, {cli.result.error}")
        raise cli.result.error
    return True


MCR_CLEANROOM_VERSIONS_REGISTRY = "mcr.microsoft.com/cleanroom"
MCR_CGS_REGISTRY = "mcr.microsoft.com/cleanroom"
mcr_cgs_constitution_url = f"{MCR_CGS_REGISTRY}/cgs-constitution:1.0.8"
mcr_cgs_jsapp_url = f"{MCR_CGS_REGISTRY}/cgs-js-app:1.0.8"

compose_file = (
    f"{os.path.dirname(__file__)}{os.path.sep}data{os.path.sep}docker-compose.yaml"
)
aspire_dashboard_compose_file = f"{os.path.dirname(__file__)}{os.path.sep}data{os.path.sep}aspire-dashboard{os.path.sep}docker-compose.yaml"

aes_encryptor_so = (
    f"{os.path.dirname(__file__)}{os.path.sep}binaries{os.path.sep}aes_encryptor.so"
)
keygenerator_sh = (
    f"{os.path.dirname(__file__)}{os.path.sep}data{os.path.sep}keygenerator.sh"
)
blob_yml = f"{os.path.dirname(__file__)}{os.path.sep}data{os.path.sep}blob.yaml"
application_yml = (
    f"{os.path.dirname(__file__)}{os.path.sep}data{os.path.sep}application.yaml"
)


def governance_client_deploy_cmd(
    cmd, ccf_endpoint: str, signing_cert, signing_key, gov_client_name, service_cert=""
):
    if not os.path.exists(signing_cert):
        raise CLIError(f"File {signing_cert} does not exist.")

    if not os.path.exists(signing_key):
        raise CLIError(f"File {signing_key} does not exist.")

    if service_cert == "" and (
        not ccf_endpoint.lower().endswith("confidential-ledger.azure.com")
    ):
        raise CLIError(
            f"--service-cert argument must be specified for {ccf_endpoint} endpoint."
        )

    from python_on_whales import DockerClient

    docker = DockerClient(
        compose_files=[compose_file], compose_project_name=gov_client_name
    )
    docker.compose.up(remove_orphans=True, detach=True)
    (_, port) = docker.compose.port(service="cgs-client", private_port=8080)
    (_, uiport) = docker.compose.port(service="cgs-ui", private_port=6300)

    cgs_endpoint = f"http://host.docker.internal:{port}"
    while True:
        try:
            r = requests.get(f"{cgs_endpoint}/swagger/index.html")
            if r.status_code == 200:
                break
            else:
                logger.warning("Waiting for cgs-client endpoint to be up...")
                sleep(5)
        except:
            logger.warning("Waiting for cgs-client endpoint to be up...")
            sleep(5)

    data = {"CcfEndpoint": ccf_endpoint}
    files = [
        ("SigningCertPemFile", ("SigningCertPemFile", open(signing_cert, "rb"))),
        ("SigningKeyPemFile", ("SigningKeyPemFile", open(signing_key, "rb"))),
    ]
    if service_cert != "":
        files.append(
            ("ServiceCertPemFile", ("ServiceCertPemFile", open(service_cert, "rb")))
        )

    r = requests.post(f"{cgs_endpoint}/configure", data=data, files=files)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))

    logger.warning(
        "cgs-client container is listening on %s. Open CGS UI at http://localhost:%s.",
        port,
        uiport,
    )


def governance_client_remove_cmd(cmd, gov_client_name):
    from python_on_whales import DockerClient

    gov_client_name = get_gov_client_name(cmd.cli_ctx, gov_client_name)
    docker = DockerClient(
        compose_files=[compose_file], compose_project_name=gov_client_name
    )
    docker.compose.down()


def governance_client_show_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/show")
    if r.status_code == 204:
        return "{}"

    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_client_version_cmd(cmd, gov_client_name=""):
    gov_client_name = get_gov_client_name(cmd.cli_ctx, gov_client_name)
    digest = get_cgs_client_digest(gov_client_name)
    version = try_get_cgs_client_version(digest)

    return {
        "cgs-client": {
            "digest": digest,
            "version": version,
        }
    }


def governance_client_get_upgrades_cmd(cmd, gov_client_name=""):
    gov_client_name = get_gov_client_name(cmd.cli_ctx, gov_client_name)
    digest = get_cgs_client_digest(gov_client_name)
    cgs_client_version = find_cgs_client_version_entry(digest)
    if cgs_client_version == None:
        raise CLIError(
            f"Could not identify version for cgs-client container image: {digest}."
        )

    latest_cgs_client_version = find_cgs_client_version_entry("latest")
    from packaging.version import Version

    upgrades = []
    current_version = Version(cgs_client_version)
    if (
        latest_cgs_client_version != None
        and Version(latest_cgs_client_version) > current_version
    ):
        upgrades.append({"clientVersion": latest_cgs_client_version})

    return {"clientVersion": str(current_version), "upgrades": upgrades}


def governance_client_show_deployment_cmd(cmd, gov_client_name=""):
    from python_on_whales import DockerClient, exceptions

    gov_client_name = get_gov_client_name(cmd.cli_ctx, gov_client_name)
    docker = DockerClient(
        compose_files=[compose_file], compose_project_name=gov_client_name
    )
    try:
        (_, port) = docker.compose.port(service="cgs-client", private_port=8080)
        (_, uiport) = docker.compose.port(service="cgs-ui", private_port=6300)

    except exceptions.DockerException as e:
        raise CLIError(
            f"Not finding a client instance running with name '{gov_client_name}'. "
            + f"Check the --governance-client parameter value."
        ) from e

    return {
        "projectName": gov_client_name,
        "ports": {"cgs-client": port, "cgs-ui": uiport},
        "uiLink": f"http://localhost:{uiport}",
    }


def governance_service_deploy_cmd(cmd, gov_client_name):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)

    # Download the constitution and js_app to deploy.
    dir_path = os.path.dirname(os.path.realpath(__file__))
    bin_folder = os.path.join(dir_path, "bin")
    if not os.path.exists(bin_folder):
        os.makedirs(bin_folder)

    constitution, bundle = download_constitution_jsapp(bin_folder)

    # Submit and accept set_constitution proposal.
    logger.warning("Deploying constitution on CCF")
    content = {
        "actions": [
            {
                "name": "set_constitution",
                "args": {"constitution": constitution},
            }
        ]
    }
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(
            f"set_constitution proposal failed with status: {r.status_code} and response: {r.text}"
        )

    # A set_constitution proposal might already be accepted if the default constitution was
    # unconditionally accepting proposals. So only vote if not already accepted.
    if r.json()["proposalState"] != "Accepted":
        proposal_id = r.json()["proposalId"]
        r = requests.post(f"{cgs_endpoint}/proposals/{proposal_id}/ballots/vote_accept")
        if r.status_code != 200:
            raise CLIError(
                f"set_constitution proposal acceptance failed with status: {r.status_code} and "
                + f"response: {r.text}"
            )
        if r.json()["proposalState"] == "Open":
            logger.warning(
                "set_constitution proposal %s remains open. "
                + "Other members need to vote their acceptance for changes to take affect.",
                proposal_id,
            )
        elif r.json()["proposalState"] == "Rejected":
            raise CLIError(f"set_constitution proposal {proposal_id} was rejected")

    # Submit and accept set_js_runtime_options proposal.
    logger.warning("Configuring js runtime options on CCF")
    content = {
        "actions": [
            {
                "name": "set_js_runtime_options",
                "args": {
                    "max_heap_bytes": 104857600,
                    "max_stack_bytes": 1048576,
                    "max_execution_time_ms": 1000,
                    "log_exception_details": True,
                    "return_exception_details": True,
                },
            }
        ]
    }
    r = requests.post(
        f"{cgs_endpoint}/proposals/create", json=content
    )  # [missing-timeout]
    if r.status_code != 200:
        raise CLIError(
            f"set_js_runtime_options proposal failed with status: {r.status_code} and response: {r.text}"
        )

    proposal_id = r.json()["proposalId"]
    r = requests.post(f"{cgs_endpoint}/proposals/{proposal_id}/ballots/vote_accept")
    if r.status_code != 200:
        raise CLIError(
            f"set_js_runtime_options proposal acceptance failed with status: {r.status_code} "
            + f"and response: {r.text}"
        )

    # Submit and accept set_js_app proposal.
    logger.warning("Deploying governance service js application on CCF")
    content = {
        "actions": [
            {
                "name": "set_js_app",
                "args": {"bundle": bundle},
            }
        ]
    }
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(
            f"set_js_app proposal failed with status: {r.status_code} and response: {r.text}"
        )

    proposal_id = r.json()["proposalId"]
    r = requests.post(f"{cgs_endpoint}/proposals/{proposal_id}/ballots/vote_accept")
    if r.status_code != 200:
        raise CLIError(
            f"set_js_app proposal acceptance failed with status: {r.status_code} and response: {r.text}"
        )
    if r.json()["proposalState"] == "Open":
        logger.warning(
            "set_js_app proposal %s remains open. "
            + "Other members need to vote their acceptance for changes to take affect.",
            proposal_id,
        )
    elif r.json()["proposalState"] == "Rejected":
        raise CLIError(f"set_js_app proposal {proposal_id} was rejected")

    # Enable the OIDC issuer by default as its required for mainline scenarios.
    r = governance_oidc_issuer_show_cmd(cmd, gov_client_name)
    if r["enabled"] != True:
        logger.warning("Enabling OIDC Issuer capability")
        r = governance_oidc_issuer_propose_enable_cmd(cmd, gov_client_name)
        proposal_id = r["proposalId"]
        r = requests.post(f"{cgs_endpoint}/proposals/{proposal_id}/ballots/vote_accept")
        if r.status_code != 200:
            raise CLIError(
                f"enable_oidc_issuer proposal acceptance failed with status: {r.status_code} and response: {r.text}"
            )
        if r.json()["proposalState"] == "Open":
            logger.warning(
                "enable_oidc_issuer proposal %s remains open. "
                + "Other members need to vote their acceptance for changes to take affect.",
                proposal_id,
            )
        elif r.json()["proposalState"] == "Rejected":
            raise CLIError(f"enable_oidc_issuer proposal {proposal_id} was rejected")

        governance_oidc_issuer_generate_signing_key_cmd(cmd, gov_client_name)
    else:
        logger.warning("OIDC Issuer capability is already enabled")


def governance_service_version_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    _, current_constitution_hash = get_current_constitution(cgs_endpoint)
    (_, _, _, canonical_current_jsapp_bundle_hash) = get_current_jsapp_bundle(
        cgs_endpoint
    )
    constitution_version = try_get_constitution_version(current_constitution_hash)
    jsapp_version = try_get_jsapp_version(canonical_current_jsapp_bundle_hash)

    return {
        "constitution": {
            "digest": f"sha256:{current_constitution_hash}",
            "version": constitution_version,
        },
        "jsapp": {
            "digest": f"sha256:{canonical_current_jsapp_bundle_hash}",
            "version": jsapp_version,
        },
    }


def governance_service_get_upgrades_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)

    _, current_constitution_hash = get_current_constitution(cgs_endpoint)
    (_, _, _, canonical_current_jsapp_bundle_hash) = get_current_jsapp_bundle(
        cgs_endpoint
    )
    upgrades = []
    constitution_version, upgrade = constitution_digest_to_version_info(
        current_constitution_hash
    )
    if upgrade != None:
        upgrades.append(upgrade)

    jsapp_version, upgrade = bundle_digest_to_version_info(
        canonical_current_jsapp_bundle_hash
    )
    if upgrade != None:
        upgrades.append(upgrade)

    return {
        "constitutionVersion": constitution_version,
        "jsappVersion": jsapp_version,
        "upgrades": upgrades,
    }


def governance_service_upgrade_constitution_cmd(
    cmd,
    constitution_version="",
    constitution_url="",
    gov_client_name="",
):
    if constitution_version and constitution_url:
        raise CLIError(
            "Both constitution_version and constitution_url cannot be specified together."
        )

    if constitution_version:
        constitution_url = f"{MCR_CGS_REGISTRY}/cgs-constitution:{constitution_version}"

    if not constitution_url:
        raise CLIError("constitution_version must be specified")

    updates = governance_service_upgrade_status_cmd(cmd, gov_client_name)
    for index, x in enumerate(updates["proposals"]):
        if x["actionName"] == "set_constitution":
            raise CLIError(
                "Open constitution proposal(s) already exist. Use 'az cleanroom governance "
                + f"service upgrade status' command to see pending proposals and "
                + f"approve/withdraw them to submit a new upgrade proposal."
            )

    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)

    dir_path = os.path.dirname(os.path.realpath(__file__))
    bin_folder = os.path.join(dir_path, "bin")
    if not os.path.exists(bin_folder):
        os.makedirs(bin_folder)

    constitution = download_constitution(bin_folder, constitution_url)
    content = {
        "actions": [
            {
                "name": "set_constitution",
                "args": {"constitution": constitution},
            }
        ]
    }
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(
            f"set_constitution proposal failed with status: {r.status_code} and response: {r.text}"
        )

    return r.json()


def governance_service_upgrade_js_app_cmd(
    cmd,
    js_app_version="",
    js_app_url="",
    gov_client_name="",
):
    if js_app_version and js_app_url:
        raise CLIError(
            "Both js_app_version and jsapp_url cannot be specified together."
        )

    if js_app_version:
        js_app_url = f"{MCR_CGS_REGISTRY}/cgs-js-app:{js_app_version}"

    if not js_app_url:
        raise CLIError("jsapp_version must be specified")

    updates = governance_service_upgrade_status_cmd(cmd, gov_client_name)
    for index, x in enumerate(updates["proposals"]):
        if x["actionName"] == "set_js_app":
            raise CLIError(
                "Open jsapp proposal(s) already exist. Use 'az cleanroom governance service "
                + f"upgrade status' command to see pending proposals and approve/withdraw "
                + f"them to submit a new upgrade proposal."
            )

    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)

    dir_path = os.path.dirname(os.path.realpath(__file__))
    bin_folder = os.path.join(dir_path, "bin")
    if not os.path.exists(bin_folder):
        os.makedirs(bin_folder)

    bundle = download_jsapp(bin_folder, js_app_url)
    content = {
        "actions": [
            {
                "name": "set_js_app",
                "args": {"bundle": bundle},
            }
        ]
    }
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(
            f"set_js_app proposal failed with status: {r.status_code} and response: {r.text}"
        )

    return r.json()


def governance_service_upgrade_status_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/checkUpdates")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_create_cmd(
    cmd, contract_id, data, gov_client_name="", version=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)

    contract = {"version": version, "data": data}
    r = requests.put(f"{cgs_endpoint}/contracts/{contract_id}", json=contract)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))


def governance_contract_show_cmd(cmd, gov_client_name="", contract_id=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/contracts/{contract_id}")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_propose_cmd(cmd, contract_id, version, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    data = {"version": version}
    r = requests.post(f"{cgs_endpoint}/contracts/{contract_id}/propose", json=data)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_vote_cmd(
    cmd, contract_id, proposal_id, action, gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    data = {"proposalId": proposal_id}
    vote_method = "vote_accept" if action == "accept" else "vote_reject"
    r = requests.post(
        f"{cgs_endpoint}/contracts/{contract_id}/{vote_method}", json=data
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_proposal_list_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/proposals")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_proposal_show_cmd(cmd, proposal_id, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/proposals/{proposal_id}")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_proposal_show_actions_cmd(cmd, proposal_id, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/proposals/{proposal_id}/actions")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_proposal_vote_cmd(cmd, proposal_id, action, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    vote_method = "vote_accept" if action == "accept" else "vote_reject"
    r = requests.post(f"{cgs_endpoint}/proposals/{proposal_id}/ballots/{vote_method}")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_proposal_withdraw_cmd(cmd, proposal_id, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/proposals/{proposal_id}/withdraw")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_deployment_generate_cmd(
    cmd,
    contract_id,
    output_dir,
    debug_mode,
    allow_all,
    use_layers_cache,
    gov_client_name="",
):
    if not os.path.exists(output_dir):
        raise CLIError(f"Output folder location {output_dir} does not exist.")

    from .utilities._helpers import get_arm_template, update_layers_from_sidecar_digests

    contract = governance_contract_show_cmd(cmd, gov_client_name, contract_id)
    contract_yaml = yaml.safe_load(contract["data"])
    validate_config(contract_yaml)
    ccf_details = governance_client_show_cmd(cmd, gov_client_name)
    ssl_cert = ccf_details["serviceCert"]
    ssl_cert_base64 = base64.b64encode(bytes(ssl_cert, "utf-8")).decode("utf-8")
    arm_template, policy_json = get_arm_template(
        contract_yaml,
        contract_id,
        ccf_details["ccfEndpoint"],
        ssl_cert_base64,
        use_layers_cache,
    )

    with open(output_dir + f"{os.path.sep}cleanroom-policy-in.json", "w") as f:
        f.write(json.dumps(policy_json, indent=2))

    if allow_all:
        cce_policy_hash = (
            "73973b78d70cc68353426de188db5dfc57e5b766e399935fb73a61127ea26d20"
        )
        cce_policy_base64 = (
            "cGFja2FnZSBwb2xpY3kKCmFwaV9zdm4gOj0gIjAuMTAuMCIKCm1vdW50X2RldmljZSA"
            + "6PSB7ImFsbG93ZWQiOiB0cnVlfQptb3VudF9vdmVybGF5IDo9IHsiYWxsb3dlZCI6I"
            + "HRydWV9CmNyZWF0ZV9jb250YWluZXIgOj0geyJhbGxvd2VkIjogdHJ1ZSwgImVudl9"
            + "saXN0IjogbnVsbCwgImFsbG93X3N0ZGlvX2FjY2VzcyI6IHRydWV9CnVubW91bnRfZGV"
            + "2aWNlIDo9IHsiYWxsb3dlZCI6IHRydWV9IAp1bm1vdW50X292ZXJsYXkgOj0geyJhbGx"
            + "vd2VkIjogdHJ1ZX0KZXhlY19pbl9jb250YWluZXIgOj0geyJhbGxvd2VkIjogdHJ1ZSw"
            + "gImVudl9saXN0IjogbnVsbH0KZXhlY19leHRlcm5hbCA6PSB7ImFsbG93ZWQiOiB0cnV"
            + "lLCAiZW52X2xpc3QiOiBudWxsLCAiYWxsb3dfc3RkaW9fYWNjZXNzIjogdHJ1ZX0Kc2h"
            + "1dGRvd25fY29udGFpbmVyIDo9IHsiYWxsb3dlZCI6IHRydWV9CnNpZ25hbF9jb250YWl"
            + "uZXJfcHJvY2VzcyA6PSB7ImFsbG93ZWQiOiB0cnVlfQpwbGFuOV9tb3VudCA6PSB7ImF"
            + "sbG93ZWQiOiB0cnVlfQpwbGFuOV91bm1vdW50IDo9IHsiYWxsb3dlZCI6IHRydWV9Cmd"
            + "ldF9wcm9wZXJ0aWVzIDo9IHsiYWxsb3dlZCI6IHRydWV9CmR1bXBfc3RhY2tzIDo9IHs"
            + "iYWxsb3dlZCI6IHRydWV9CnJ1bnRpbWVfbG9nZ2luZyA6PSB7ImFsbG93ZWQiOiB0cnV"
            + "lfQpsb2FkX2ZyYWdtZW50IDo9IHsiYWxsb3dlZCI6IHRydWV9CnNjcmF0Y2hfbW91bnQ"
            + "gOj0geyJhbGxvd2VkIjogdHJ1ZX0Kc2NyYXRjaF91bm1vdW50IDo9IHsiYWxsb3dlZCI6IHRydWV9Cg=="
        )
    else:
        placeholder_rego_file_name = "cleanroom-policy-placeholder-layers.rego"
        policy_rego_file_name = (
            "cleanroom-policy.rego"
            if not use_layers_cache
            else placeholder_rego_file_name
        )

        cmd = (
            f"confcom acipolicygen -i {output_dir}{os.path.sep}cleanroom-policy-in.json "
            + f"--outraw-pretty-print -s {output_dir}{os.path.sep}{policy_rego_file_name}"
        )

        if debug_mode:
            cmd += " --debug-mode"
        result = az_cli(cmd)
        print(f"Result: {result}")

        if use_layers_cache:
            logger.warning(
                "Using layers cache to replace placeholder dmverity layer hashes in the cce policy"
            )
            with open(
                f"{output_dir}{os.path.sep}{placeholder_rego_file_name}", "r"
            ) as f:
                cce_policy_lines = [line.rstrip() for line in f]

            # Read the container array from rego as a JSON array, replace the placeholder layers
            # that were computed for the k8s.gcr.io/pause container with the values from the
            # sidecar-digests document and then update the rego with the revised containers array.
            startIndex = cce_policy_lines.index("containers := [")
            stopIndex = cce_policy_lines.index("]", startIndex)
            containers_array_from_rego = """
            {}
            """.format(
                "\n".join(cce_policy_lines[startIndex + 1 : stopIndex + 1])
            )
            containers_json = "[" + containers_array_from_rego
            containers = json.loads(containers_json)

            # Generating tmp files to aid debugging if the need arises.
            with open(
                output_dir
                + f"{os.path.sep}cleanroom-policy-containers-placeholder-layers.tmp",
                "w",
            ) as f:
                f.write(json.dumps(containers, indent=2))

            update_layers_from_sidecar_digests(contract_yaml, output_dir, containers)

            with open(
                output_dir
                + f"{os.path.sep}cleanroom-policy-containers-updated-layers.tmp",
                "w",
            ) as f:
                f.write(json.dumps(containers, indent=2))

            # Write out the final rego with the containers array substituted and everything
            # else remaining as-is.
            revised_cce_policy = cce_policy_lines[:startIndex]
            revised_cce_policy.append(
                "containers := " + json.dumps(containers, indent=2)
            )
            revised_cce_policy += cce_policy_lines[stopIndex + 1 :]
            new_line = ""
            with open(output_dir + f"{os.path.sep}cleanroom-policy.rego", "w") as f:
                for line in revised_cce_policy:
                    f.write(f"{new_line}{line}")
                    new_line = "\n"

        with open(f"{output_dir}{os.path.sep}cleanroom-policy.rego", "r") as f:
            cce_policy = f.read()

        cce_policy_base64 = base64.b64encode(bytes(cce_policy, "utf-8")).decode("utf-8")
        cce_policy_hash = hashlib.sha256(bytes(cce_policy, "utf-8")).hexdigest()

    arm_template["resources"][0]["properties"]["confidentialComputeProperties"][
        "ccePolicy"
    ] = cce_policy_base64

    with open(output_dir + f"{os.path.sep}cleanroom-arm-template.json", "w") as f:
        f.write(json.dumps(arm_template, indent=2))

    policy_json = {
        "type": "add",
        "claims": {
            "x-ms-sevsnpvm-is-debuggable": False,
            "x-ms-sevsnpvm-hostdata": cce_policy_hash,
        },
    }

    with open(output_dir + f"{os.path.sep}cleanroom-governance-policy.json", "w") as f:
        f.write(json.dumps(policy_json, indent=2))


def governance_deployment_template_propose_cmd(
    cmd, contract_id, template_file, gov_client_name=""
):
    if not os.path.exists(template_file):
        raise CLIError(
            f"File {template_file} not found. Check the input parameter value."
        )

    with open(template_file, encoding="utf-8") as f:
        template_json = json.loads(f.read())

    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(
        f"{cgs_endpoint}/contracts/{contract_id}/deploymentspec/propose",
        json=template_json,
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_deployment_template_show_cmd(cmd, contract_id, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/contracts/{contract_id}/deploymentspec")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_deployment_policy_propose_cmd(
    cmd, contract_id, allow_all=None, policy_file="", gov_client_name=""
):
    if not allow_all and policy_file == "":
        raise CLIError("Either --policy-file or --allow-all flag must be specified")

    if allow_all and policy_file != "":
        raise CLIError(
            "Both --policy-file and --allow-all cannot be specified together"
        )

    if allow_all:
        policy_json = {
            "type": "add",
            "claims": {
                "x-ms-sevsnpvm-is-debuggable": False,
                "x-ms-sevsnpvm-hostdata": "73973b78d70cc68353426de188db5dfc57e5b766e399935fb73a61127ea26d20",
            },
        }
    else:
        if not os.path.exists(policy_file):
            raise CLIError(
                f"File {policy_file} not found. Check the input parameter value."
            )

        with open(policy_file, encoding="utf-8") as f:
            policy_json = json.loads(f.read())

    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(
        f"{cgs_endpoint}/contracts/{contract_id}/cleanroompolicy/propose",
        json=policy_json,
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_deployment_policy_show_cmd(cmd, contract_id, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/contracts/{contract_id}/cleanroompolicy")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_oidc_issuer_propose_enable_cmd(cmd, gov_client_name=""):
    content = {
        "actions": [{"name": "enable_oidc_issuer", "args": {"kid": uuid.uuid4().hex}}]
    }
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_oidc_issuer_generate_signing_key_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/oidc/generateSigningKey")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_oidc_issuer_propose_rotate_signing_key_cmd(cmd, gov_client_name=""):
    content = {
        "actions": [{"name": "oidc_issuer_enable_rotate_signing_key", "args": {}}]
    }
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_oidc_issuer_set_issuer_url_cmd(cmd, url, gov_client_name=""):
    content = {"url": url}
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/oidc/setIssuerUrl", json=content)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))


def governance_oidc_issuer_propose_set_issuer_url_cmd(cmd, url, gov_client_name=""):
    content = {
        "actions": [{"name": "set_oidc_issuer_url", "args": {"issuer_url": url}}]
    }
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_oidc_issuer_show_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/oidc/issuerInfo")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_runtime_option_get_cmd(
    cmd, contract_id, option_name, gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(
        f"{cgs_endpoint}/contracts/{contract_id}/checkstatus/{option_name}"
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_runtime_option_set_cmd(
    cmd, contract_id, option_name, action, gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/contracts/{contract_id}/{option_name}/{action}")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))


def governance_contract_runtime_option_propose_cmd(
    cmd, contract_id, option_name, action, gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(
        f"{cgs_endpoint}/contracts/{contract_id}/{option_name}/propose-{action}"
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_secret_set_cmd(
    cmd, contract_id, secret_name, value, gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    content = {"value": value}
    r = requests.put(
        f"{cgs_endpoint}/contracts/{contract_id}/secrets/{secret_name}", json=content
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_contract_event_list_cmd(
    cmd, contract_id, all=None, event_id="", scope="", gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    query_url = f"{cgs_endpoint}/contracts/{contract_id}/events"
    query = ""
    if event_id != "":
        query += f"&id=all{event_id}"
    if scope != "":
        query += f"&scope={scope}"
    if all:
        query += "&from_seqno=1"

    if query != "":
        query_url += f"?{query}"

    r = requests.get(f"{query_url}")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_document_create_cmd(
    cmd, document_id, contract_id, data, gov_client_name="", version=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    document = {"version": version, "contractId": contract_id, "data": data}
    r = requests.put(f"{cgs_endpoint}/documents/{document_id}", json=document)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))


def governance_document_show_cmd(cmd, gov_client_name="", document_id=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/documents/{document_id}")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_document_propose_cmd(cmd, document_id, version, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    data = {"version": version}
    r = requests.post(f"{cgs_endpoint}/documents/{document_id}/propose", json=data)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_document_vote_cmd(
    cmd, document_id, proposal_id, action, gov_client_name=""
):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    data = {"proposalId": proposal_id}
    vote_method = "vote_accept" if action == "accept" else "vote_reject"
    r = requests.post(
        f"{cgs_endpoint}/documents/{document_id}/{vote_method}", json=data
    )
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_member_add_cmd(
    cmd, identifier, tenant_id, certificate, gov_client_name=""
):
    if not os.path.exists(certificate):
        raise CLIError(f"File {certificate} does not exist.")

    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    with open(certificate, encoding="utf-8") as f:
        cert_pem = f.read()
    member_data = {"identifier": identifier}
    if tenant_id != "":
        member_data["tenant_id"] = tenant_id
    content = {
        "actions": [
            {
                "name": "set_member",
                "args": {"cert": cert_pem, "member_data": member_data},
            }
        ]
    }

    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_member_set_tenant_id_cmd(cmd, identifier, tenant_id, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    member_data = {"identifier": identifier, "tenant_id": tenant_id}
    members = governance_member_show_cmd(cmd, gov_client_name)
    member = [
        x
        for x in members
        if "identifier" in members[x]["member_data"]
        and members[x]["member_data"]["identifier"] == identifier
    ]
    if len(member) == 0:
        raise CLIError(f"Member with identifier {identifier} was not found.")

    content = {
        "actions": [
            {
                "name": "set_member_data",
                "args": {
                    "member_id": member[0],
                    "member_data": member_data,
                },
            }
        ]
    }

    r = requests.post(f"{cgs_endpoint}/proposals/create", json=content)
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_member_activate_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.post(f"{cgs_endpoint}/members/statedigests/ack")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))


def governance_member_show_cmd(cmd, gov_client_name=""):
    cgs_endpoint = get_cgs_client_endpoint(cmd, gov_client_name)
    r = requests.get(f"{cgs_endpoint}/members")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    return r.json()


def governance_member_keygeneratorsh_cmd(cmd):
    with open(keygenerator_sh, encoding="utf-8") as f:
        print(f.read())


def get_cgs_client_endpoint(cmd, gov_client_name: str):
    port = get_cgs_client_port(cmd, gov_client_name)
    return f"http://host.docker.internal:{port}"


def get_cgs_client_port(cmd, gov_client_name: str):
    gov_client_name = get_gov_client_name(cmd.cli_ctx, gov_client_name)

    # Note (gsinha): Not using python_on_whales here as its load time is found to be slow and this
    # method gets invoked frequently to determin the client port. using the docker package instead.
    # from python_on_whales import DockerClient, exceptions
    try:
        import docker

        client = docker.from_env()
        container_name = f"{gov_client_name}-cgs-client-1"
        container = client.containers.get(container_name)
        port = container.ports["8080/tcp"][0]["HostPort"]
        # docker = DockerClient(
        #     compose_files=[compose_file], compose_project_name=gov_client_name
        # )
        # (_, port) = docker.compose.port(service="cgs-client", private_port=8080)
        return port
    # except exceptions.DockerException as e:
    except Exception as e:
        raise CLIError(
            f"Not finding a client instance running with name '{gov_client_name}'. Check "
            + "the --governance-client parameter value."
        ) from e


def get_gov_client_name(cli_ctx, gov_client_name):
    if gov_client_name != "":
        return gov_client_name

    gov_client_name = cli_ctx.config.get("cleanroom", "governance.client_name", "")

    if gov_client_name == "":
        raise CLIError(
            "--governance-client=<value> parameter must be specified or set a default "
            + "value via `az config set cleanroom governance.client_name=<value>`"
        )

    logger.debug('Current value of "gov_client_name": %s.', gov_client_name)
    return gov_client_name


def response_error_message(r: requests.Response):
    return f"{r.request.method} {r.request.url} failed with status: {r.status_code} response: {r.text}"


def get_keys_dir_path(cleanroom_config):
    file_name, _ = os.path.splitext(os.path.abspath(cleanroom_config))
    keys_dir = f"{file_name}.keys"
    return keys_dir


def get_private_config_file_name(cleanroom_config):
    file_name, file_ext = os.path.splitext(cleanroom_config)
    cleanroom_config_private = file_name + ".private" + file_ext
    return cleanroom_config_private


def get_cleanroom_config(cleanroom_config):
    try:
        with open(cleanroom_config, "r") as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        raise CLIError(
            f"Cannot find file {cleanroom_config}. Check the --cleanroom-config parameter value."
        )

    return config


def write_cleanroom_config(cleanroom_config, config):
    with open(cleanroom_config, "w") as f:
        yaml.dump(config, f, default_flow_style=False)


def get_cleanroom_private_config(cleanroom_config):
    cleanroom_config_private = get_private_config_file_name(cleanroom_config)
    try:
        with open(cleanroom_config_private, "r") as f:
            private_config = yaml.safe_load(f)
    except FileNotFoundError:
        raise CLIError(
            f"Cannot find file {cleanroom_config_private}. Check the --cleanroom-config parameter value."
        )

    return private_config


def write_cleanroom_private_config(cleanroom_config, private_config):
    cleanroom_config_private = get_private_config_file_name(cleanroom_config)
    with open(cleanroom_config_private, "w") as f:
        yaml.dump(private_config, f, default_flow_style=False)


def get_dataset(blobDetails):
    with open(blob_yml, "r") as f:
        data = f.read()

    for key in blobDetails:
        data = data.replace(key, blobDetails[key])

    dataset = yaml.safe_load(data)
    return dataset


def get_application(applicationDetails):
    with open(application_yml, "r") as f:
        data = f.read()

    for key in applicationDetails:
        data = data.replace(key, applicationDetails[key])

    application = yaml.safe_load(data)
    return application


def add_datastore(
    storage_account,
    container_name,
    name,
    identity,
    dek_key_vault,
    wrapped_dek_name,
    is_read_only,
):
    storage_account_url = az_cli(
        f"storage account show --ids {storage_account} --query primaryEndpoints.blob"
    )
    dek_key_vault_url = az_cli(
        f"resource show --id {dek_key_vault} --query properties.vaultUri"
    )
    identity = az_cli(f"resource show --id {identity} --query properties")
    blobDetails = {
        "__NAME__": name,
        "__CONTAINER_NAME__": container_name,
        "__READONLY__": "Volume__ReadOnly" if is_read_only else "Volume__ReadWrite",
        "__SA_URL__": storage_account_url,
        "__PROXY_TYPE__": (
            "SecureVolume__ReadOnly__AzureStorage__BlobContainer"
            if is_read_only
            else "SecureVolume__ReadWrite__AzureStorage__BlobContainer"
        ),
        "__IDENTITY__": json.dumps(identity),
        "__WRAPPED_DEK_NAME__": wrapped_dek_name,
        "__AZURE_KEYVAULT_URL__": dek_key_vault_url,
    }

    return get_dataset(blobDetails)


def config_init_cmd(cmd, cleanroom_config):

    if os.path.exists(cleanroom_config):
        logger.warning(f"{cleanroom_config} already exists. Doing nothing.")
        return
    private_config = get_private_config_file_name(cleanroom_config)
    if os.path.exists(private_config):
        logger.warning(f"{private_config} already exists. Doing nothing.")
        return
    keys_dir = get_keys_dir_path(cleanroom_config)
    if not os.path.exists(keys_dir):
        os.makedirs(keys_dir)

    init_config = {
        "identities": [],
        "specification": {
            "datasources": [],
            "datasinks": [],
            "applications": [],
            "telemetry": {},
        },
    }
    write_cleanroom_config(cleanroom_config, init_config)
    write_cleanroom_private_config(cleanroom_config, [])


def merge_config(this, that):
    for key in that:
        if key in this:
            if isinstance(this[key], dict) and isinstance(that[key], dict):
                merge_config(this[key], that[key])
            elif isinstance(this[key], list) and isinstance(that[key], list):
                this[key].extend(that[key])
            else:
                this[key] = that[key]
        else:
            this[key] = that[key]


def config_view_cmd(cmd, cleanroom_config, configs, no_print):

    with open(cleanroom_config, "r") as f:
        conf = yaml.safe_load(f)

    # Merge cleanroom_config yaml and other yamls in configs
    for config in configs:
        with open(config, "r") as f:
            merge_config(conf, yaml.safe_load(f))

    # Delete the kek section as every datasource / datasink would have
    # the information embedded in them.
    if "kek" in conf:
        del conf["kek"]

    c = yaml.dump(conf, default_flow_style=False)
    if no_print:
        return c

    print(c)


def config_set_kek_cmd(cmd, cleanroom_config, kek_key_vault, maa_url):
    kv_url = az_cli(f"resource show --id {kek_key_vault} --query properties.vaultUri")

    config = get_cleanroom_config(cleanroom_config)

    existing_generate_name = config["kek"]["generateName"] if "kek" in config else None
    config["kek"] = {
        "generateName": existing_generate_name or str(uuid.uuid4())[:8] + "-",
        "__HSM_URL__": kv_url,
        "__MAA_URL__": maa_url,
    }

    write_cleanroom_config(cleanroom_config, config)
    logger.warning(f"Kek entry added to cleanroom configuration.")


def config_create_kek_policy_cmd(cmd, cleanroom_config, contract_id, b64_cl_policy):
    cl_policy = json.loads(base64.b64decode(b64_cl_policy).decode("utf-8"))
    create_kek_with_cl_policy(cmd, cleanroom_config, contract_id, cl_policy)


def config_wrap_deks_cmd(cmd, cleanroom_config, contract_id, gov_client_name=""):
    if gov_client_name != "":
        # Create the KEK first that will be used to wrap the DEKs.
        create_kek_via_governance(cmd, cleanroom_config, contract_id, gov_client_name)

    config_wrap_deks(cmd, cleanroom_config, contract_id)


def config_wrap_secret_cmd(
    cmd,
    cleanroom_config,
    contract_id,
    name: str,
    value: str,
    secret_key_vault,
    gov_client_name="",
):
    if gov_client_name != "":
        # Create the KEK first that will be used to wrap the DEKs.
        create_kek_via_governance(cmd, cleanroom_config, contract_id, gov_client_name)

    config = get_cleanroom_config(cleanroom_config)

    if not "kek" in config:
        raise CLIError("Run az cleanroom config set-kek first.")

    cleanroom_config_private = cleanroom_config + ".private"
    with open(cleanroom_config_private, "r") as f:
        private_config = yaml.safe_load(f)

    kek_name = "kek/" + config["kek"]["generateName"] + contract_id
    kek = [pc for pc in private_config if pc["name"] == kek_name]
    if len(kek) == 0:
        raise CLIError(
            "Kek not found. Run 'az cleanroom create-kek' first or pass in "
            + "--governance-client parameter to this command to create the kek automatically."
        )
    if len(kek) > 1:
        raise CLIError(
            f"Found more than one key entry name with name {kek_name}. This is not supported."
        )

    with open(kek[0]["keyFilePath"], "rb") as key_file:
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives import hashes

        private_key = serialization.load_pem_private_key(key_file.read(), password=None)

    public_key = private_key.public_key()

    # Wrap the supplied secret
    ciphertext = base64.b64encode(
        public_key.encrypt(
            value.encode("utf-8"),
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None,
            ),
        )
    ).decode()

    secret_name = name
    vault_url = az_cli(
        f"resource show --id {secret_key_vault} --query properties.vaultUri"
    )
    vault_name = urlparse(vault_url).hostname.split(".")[0]

    logger.warning(
        f"Creating wrapped secret '{secret_name}' in key vault '{vault_name}'."
    )
    az_cli(
        f"keyvault secret set --name {secret_name} --vault-name {vault_name} --value {ciphertext}"
    )

    return {
        "kid": secret_name,
        "akvEndpoint": vault_url,
        "kek": {
            "kid": config["kek"]["generateName"] + contract_id,
            "akvEndpoint": config["kek"]["__HSM_URL__"],
            "maaEndpoint": config["kek"]["__MAA_URL__"],
        },
    }


def config_add_datasource_cmd(
    cmd,
    cleanroom_config,
    storage_account,
    name,
    identity,
    dek_key_vault,
    container_name="",
):
    container_name = container_name or name

    config = get_cleanroom_config(cleanroom_config)

    if not "kek" in config:
        raise CLIError("Run az cleanroom config set-kek first.")

    key_file_path = get_keys_dir_path(cleanroom_config)
    storage_account_name = az_cli(
        f"storage account show --ids {storage_account} --query name"
    )
    logger.warning(
        f"Creating storage container '{container_name}' in {storage_account}."
    )
    container = az_cli(
        f"storage container create --name {container_name} --account-name {storage_account_name} --auth-mode login"
    )

    key_file_path = os.path.abspath(os.path.join(key_file_path, f"{name}.bin"))
    if not os.path.exists(key_file_path):
        from Crypto.Random import get_random_bytes

        encryption_key = get_random_bytes(32)
        with open(key_file_path, "wb") as key_file:
            key_file.write(encryption_key)

    wrapped_dek_name = f"wrapped-{name}-dek"
    datasource = add_datastore(
        storage_account,
        container_name,
        name,
        identity,
        dek_key_vault,
        wrapped_dek_name,
        True,
    )

    private_config = get_cleanroom_private_config(cleanroom_config)

    datasource["Protection"]["EncryptionSecret"]["KEK"]["BackingResource"][
        "NamePrefix"
    ] = config["kek"]["generateName"]
    datasource["Protection"]["EncryptionSecret"]["KEK"]["BackingResource"]["Provider"][
        "Configuration"
    ] = config["kek"]["__MAA_URL__"]
    datasource["Protection"]["EncryptionSecret"]["KEK"]["BackingResource"]["Provider"][
        "URL"
    ] = config["kek"]["__HSM_URL__"]

    if config["specification"]["datasources"] is None:
        config["specification"]["datasources"] = []

    identity_config = az_cli(f"resource show --id {identity} --query properties")
    for index, x in enumerate(config["identities"]):
        if x["clientId"] == identity_config["clientId"]:
            config["identities"][index] = identity_config
            break
    else:
        config["identities"].append(identity_config)

    entry = {"name": name, "datasource": datasource}
    for index, x in enumerate(config["specification"]["datasources"]):
        if x["name"] == entry["name"]:
            config["specification"]["datasources"][index] = entry
            break
    else:
        config["specification"]["datasources"].append(entry)

    private_entry = {"name": "datasource/" + name, "keyFilePath": key_file_path}
    for index, x in enumerate(private_config):
        if x["name"] == private_entry["name"]:
            private_config[index] = private_entry
            break
    else:
        private_config.append(private_entry)

    write_cleanroom_config(cleanroom_config, config)

    write_cleanroom_private_config(cleanroom_config, private_config)
    logger.warning(f"Datasource '{name}' added to cleanroom configuration.")


def config_add_datasink_cmd(
    cmd,
    cleanroom_config,
    storage_account,
    name,
    identity,
    dek_key_vault,
    container_name="",
):
    container_name = container_name or name

    config = get_cleanroom_config(cleanroom_config)

    if not "kek" in config:
        raise CLIError("Run az cleanroom config set-kek first.")

    key_file_path = get_keys_dir_path(cleanroom_config)
    logger.warning(
        f"Creating storage container '{container_name}' in {storage_account}."
    )
    storage_account_name = az_cli(
        f"storage account show --ids {storage_account} --query name"
    )
    container = az_cli(
        f"storage container create --name {container_name} --account-name {storage_account_name} --auth-mode login"
    )

    from Crypto.Random import get_random_bytes

    encryption_key = get_random_bytes(32)
    key_file_path = os.path.abspath(os.path.join(key_file_path, f"{name}.bin"))
    with open(key_file_path, "wb") as key_file:
        key_file.write(encryption_key)

    wrapped_dek_name = f"wrapped-{name}-dek"
    datasink = add_datastore(
        storage_account,
        container_name,
        name,
        identity,
        dek_key_vault,
        wrapped_dek_name,
        False,
    )

    private_config = get_cleanroom_private_config(cleanroom_config)

    datasink["Protection"]["EncryptionSecret"]["KEK"]["BackingResource"][
        "NamePrefix"
    ] = config["kek"]["generateName"]
    datasink["Protection"]["EncryptionSecret"]["KEK"]["BackingResource"]["Provider"][
        "Configuration"
    ] = config["kek"]["__MAA_URL__"]
    datasink["Protection"]["EncryptionSecret"]["KEK"]["BackingResource"]["Provider"][
        "URL"
    ] = config["kek"]["__HSM_URL__"]

    if config["specification"]["datasinks"] is None:
        config["specification"]["datasinks"] = []

    identity_config = az_cli(f"resource show --id {identity} --query properties")
    for index, x in enumerate(config["identities"]):
        if x["clientId"] == identity_config["clientId"]:
            config["identities"][index] = identity_config
            break
    else:
        config["identities"].append(identity_config)

    entry = {"name": name, "datasink": datasink}
    for index, x in enumerate(config["specification"]["datasinks"]):
        if x["name"] == entry["name"]:
            config["specification"]["datasinks"][index] = entry
            break
    else:
        config["specification"]["datasinks"].append(entry)

    private_entry = {"name": "datasink/" + name, "keyFilePath": key_file_path}
    for index, x in enumerate(private_config):
        if x["name"] == private_entry["name"]:
            private_config[index] = private_entry
            break
    else:
        private_config.append(private_entry)

    write_cleanroom_config(cleanroom_config, config)

    write_cleanroom_private_config(cleanroom_config, private_config)
    logger.warning(f"Datasink {name} added to cleanroom configuration.")


def config_set_telemetry_cmd(
    cmd, cleanroom_config, storage_account, identity, dek_key_vault, container_name=""
):
    config_add_datasink_cmd(
        cmd,
        cleanroom_config,
        storage_account,
        "infrastructure-telemetry",
        identity,
        dek_key_vault,
        container_name,
    )

    config = get_cleanroom_config(cleanroom_config)

    if config["specification"]["telemetry"] is None:
        config["specification"]["telemetry"] = {}
    config["specification"]["telemetry"]["infrastructure"] = {
        "metrics": "infrastructure-telemetry",
        "logs": "infrastructure-telemetry",
        "traces": "infrastructure-telemetry",
    }

    write_cleanroom_config(cleanroom_config, config)


def config_set_logging_cmd(
    cmd, cleanroom_config, storage_account, identity, dek_key_vault, container_name=""
):
    config_add_datasink_cmd(
        cmd,
        cleanroom_config,
        storage_account,
        "application-telemetry",
        identity,
        dek_key_vault,
        container_name,
    )

    config = get_cleanroom_config(cleanroom_config)

    if config["specification"]["telemetry"] is None:
        config["specification"]["telemetry"] = {}
    config["specification"]["telemetry"]["application"] = {
        "metrics": "application-telemetry",
        "logs": "application-telemetry",
        "traces": "application-telemetry",
    }

    write_cleanroom_config(cleanroom_config, config)


def config_add_application_cmd(
    cmd,
    cleanroom_config,
    name,
    image,
    cpu,
    memory,
    command_line=None,
    mounts={},
    env_vars={},
    ports=None,
):
    config = get_cleanroom_config(cleanroom_config)

    application_details = {
        "__NAME__": name,
        "__IMAGE_ID__": image,
        "__REGISTRY_URL__": image.split("/")[0],
        "__CPU__": cpu,
        "__MEMORY__": memory,
    }

    ports = ports or []
    command = shlex.split(command_line) if command_line else None
    application = get_application(application_details)
    application.update(
        {
            "command": command,
            "mount": [key + ":" + value for key, value in mounts.items()],
            "env_var": [key + "=" + value for key, value in env_vars.items()],
            "ports": ports,
        }
    )
    # logger.warning(f"Adding application {name} to cleanroom config {config}")
    if config["specification"]["applications"] is None:
        config["specification"]["applications"] = []

    entry = {"name": name, "application": application}
    for index, x in enumerate(config["specification"]["applications"]):
        if x["name"] == entry["name"]:
            config["specification"]["applications"][index] = entry
            break
    else:
        config["specification"]["applications"].append(entry)

    write_cleanroom_config(cleanroom_config, config)
    logger.warning(f"Application {name} added to cleanroom configuration.")


def config_disable_sandbox_cmd(cmd, cleanroom_config):
    config = get_cleanroom_config(cleanroom_config)
    config["sandbox"] = "disabled"
    write_cleanroom_config(cleanroom_config, config)


def config_enable_sandbox_cmd(cmd, cleanroom_config):
    config = get_cleanroom_config(cleanroom_config)
    config["sandbox"] = "enabled"
    write_cleanroom_config(cleanroom_config, config)


def config_set_network_policy_cmd(cmd, cleanroom_config, policy_bundle_url, allow_all):
    if not allow_all and not policy_bundle_url:
        raise CLIError(
            "Either --policy-bundle-url or --allow-all flag must be specified"
        )

    if allow_all and policy_bundle_url:
        raise CLIError(
            "Both --policy-bundle-url and --allow-all cannot be specified together"
        )

    config = get_cleanroom_config(cleanroom_config)
    config["networkPolicy"] = {
        "policyBundleUrl": policy_bundle_url or "",
        "allowAll": "true" if allow_all else "false",
    }
    write_cleanroom_config(cleanroom_config, config)


def config_remove_network_policy_cmd(cmd, cleanroom_config):
    config = get_cleanroom_config(cleanroom_config)
    if "networkPolicy" in config:
        del config["networkPolicy"]
        write_cleanroom_config(cleanroom_config, config)


def config_validate_cmd(cmd, cleanroom_config):
    config = get_cleanroom_config(cleanroom_config)
    validate_config(config)


def datasource_upload_cmd(cmd, cleanroom_config, datasource_name, dataset_folder):
    private_config = get_cleanroom_private_config(cleanroom_config)
    config = get_cleanroom_config(cleanroom_config)
    datasources = [
        x
        for x in config["specification"]["datasources"]
        if x["name"] == datasource_name
    ]
    if len(datasources) == 0:
        raise CLIError(
            f"Datasource {datasource_name} not found in cleanroom configuration."
        )
    datasource = datasources[0]["datasource"]

    # Get the key path.
    key_file_path = [
        x for x in private_config if x["name"] == "datasource/" + datasource_name
    ][0]["keyFilePath"]

    with open(key_file_path, "rb") as f:
        encryption_key = f.read()
    encryption_key_base_64 = base64.b64encode(encryption_key).decode("utf-8")
    encryption_key_sha256 = hashlib.sha256(encryption_key).digest()
    encryption_key_sha256_base_64 = base64.b64encode(encryption_key_sha256).decode(
        "utf-8"
    )

    # Get the tenant Id of the datasource and indicate azcopy to use the tenant Id.
    # https://learn.microsoft.com/en-us/azure/storage/common/storage-ref-azcopy-configuration-settings
    tenant_id = datasource["Identity"]["tenantId"]
    os.environ["AZCOPY_TENANT_ID"] = tenant_id

    azcopy_auto_login_type = "AZCLI"
    is_msi = az_cli("account show --query user.assignedIdentityInfo -o tsv")
    if is_msi == "MSI":
        azcopy_auto_login_type = "MSI"

    # azcopy with CPK needs the values below for encryption
    # https://learn.microsoft.com/en-us/azure/storage/common/storage-ref-azcopy-copy
    os.environ["CPK_ENCRYPTION_KEY"] = encryption_key_base_64
    os.environ["CPK_ENCRYPTION_KEY_SHA256"] = encryption_key_sha256_base_64
    os.environ["AZCOPY_AUTO_LOGIN_TYPE"] = azcopy_auto_login_type
    container_url = datasource["Store"]["Provider"]["URL"] + datasource["Store"]["Name"]
    logger.warning(f"Uploading dataset {dataset_folder} to {container_url}")
    file_path = dataset_folder + f"{os.path.sep}*"

    import subprocess

    result: subprocess.CompletedProcess
    try:
        result = subprocess.run(
            [
                "azcopy",
                "copy",
                file_path,
                container_url,
                "--recursive",
                "--cpk-by-value",
            ],
            capture_output=True,
        )
    except FileNotFoundError:
        raise CLIError(
            "azcopy not installed. Install from https://github.com/Azure/azure-storage-azcopy?tab=readme-ov-file#download-azcopy and try again."
        )

    try:
        for line in str.splitlines(result.stdout.decode()):
            logger.warning(line)
        for line in str.splitlines(result.stderr.decode()):
            logger.warning(line)
        result.check_returncode()
    except subprocess.CalledProcessError:
        for line in str.splitlines(result.stdout.decode()):
            logger.error(line)
        for line in str.splitlines(result.stderr.decode()):
            logger.error(line)
        raise CLIError("Failed to upload dataset. See error details above.")


def datasink_download_cmd(cmd, cleanroom_config, datasink_name, target_folder):
    azcopy_download(datasink_name, cleanroom_config, target_folder)


def telemetry_download_cmd(cmd, cleanroom_config, target_folder):
    azcopy_download("infrastructure-telemetry", cleanroom_config, target_folder)


def logs_download_cmd(cmd, cleanroom_config, target_folder):
    azcopy_download("application-telemetry", cleanroom_config, target_folder)


def telemetry_aspire_dashboard_cmd(cmd, telemetry_folder, project_name=""):
    from python_on_whales import DockerClient

    project_name = project_name or "cleanroom-aspire-dashboard"
    os.environ["TELEMETRY_FOLDER"] = os.path.abspath(telemetry_folder)
    docker = DockerClient(
        compose_files=[aspire_dashboard_compose_file],
        compose_project_name=project_name,
    )
    docker.compose.up(remove_orphans=True, detach=True)
    (_, port) = docker.compose.port(service="aspire", private_port=18888)

    logger.warning("Open Aspire Dashboard at http://localhost:%s.", port)


def azcopy_download(datasink_name, cleanroom_config, target_folder):
    private_config = get_cleanroom_private_config(cleanroom_config)
    config = get_cleanroom_config(cleanroom_config)
    datasinks = [
        x for x in config["specification"]["datasinks"] if x["name"] == datasink_name
    ]
    if len(datasinks) == 0:
        raise CLIError(
            f"Datasink {datasink_name} not found in cleanroom configuration."
        )
    datasink = datasinks[0]["datasink"]
    container_url = datasink["Store"]["Provider"]["URL"] + datasink["Store"]["Name"]
    key_file_path = [
        x for x in private_config if x["name"] == "datasink/" + datasink_name
    ][0]["keyFilePath"]

    with open(key_file_path, "rb") as f:
        encryption_key = f.read()
    encryption_key_base_64 = base64.b64encode(encryption_key).decode("utf-8")
    encryption_key_sha256 = hashlib.sha256(encryption_key).digest()
    encryption_key_sha256_base_64 = base64.b64encode(encryption_key_sha256).decode(
        "utf-8"
    )

    # Get the tenant Id of the datasink and indicate azcopy to use the tenant Id.
    # https://learn.microsoft.com/en-us/azure/storage/common/storage-ref-azcopy-configuration-settings
    tenant_id = datasink["Identity"]["tenantId"]
    os.environ["AZCOPY_TENANT_ID"] = tenant_id

    azcopy_auto_login_type = "AZCLI"
    is_msi = az_cli("account show --query user.assignedIdentityInfo -o tsv")
    if is_msi == "MSI":
        azcopy_auto_login_type = "MSI"

    # azcopy with CPK needs the values below for encryption
    # https://learn.microsoft.com/en-us/azure/storage/common/storage-ref-azcopy-copy
    os.environ["CPK_ENCRYPTION_KEY"] = encryption_key_base_64
    os.environ["CPK_ENCRYPTION_KEY_SHA256"] = encryption_key_sha256_base_64
    os.environ["AZCOPY_AUTO_LOGIN_TYPE"] = azcopy_auto_login_type
    logger.warning(f"Downloading datasink {container_url} to {target_folder}")

    import subprocess

    result: subprocess.CompletedProcess
    try:
        result = subprocess.run(
            [
                "azcopy",
                "copy",
                container_url,
                target_folder,
                "--recursive",
                "--cpk-by-value",
            ],
            capture_output=True,
        )
    except FileNotFoundError:
        raise CLIError(
            "azcopy not installed. Install from https://github.com/Azure/azure-storage-azcopy?tab=readme-ov-file#download-azcopy and try again."
        )

    try:
        for line in str.splitlines(result.stdout.decode()):
            logger.warning(line)
        for line in str.splitlines(result.stderr.decode()):
            logger.warning(line)
        result.check_returncode()
    except subprocess.CalledProcessError:
        for line in str.splitlines(result.stdout.decode()):
            logger.error(line)
        for line in str.splitlines(result.stderr.decode()):
            logger.error(line)
        raise CLIError("Failed to download dataset. See error details above.")


# TODO (gsinha): Remove once demonstration purpose is finished.
def datastore_encryptor_encrypt_cmd(cmd):
    # https://medium.com/analytics-vidhya/running-go-code-from-python-a65b3ae34a2d
    # https://fluhus.github.io/snopher/
    import ctypes

    lib = ctypes.CDLL(aes_encryptor_so)
    encrypt = lib.GoEncryptChunk
    encrypt.argtypes = [ctypes.c_char_p]
    encrypt.restype = ctypes.c_void_p

    document = {
        "Data": base64.b64encode(b"somedatabytes").decode(),
        "Key": base64.b64encode(b"somekeybytes").decode(),
    }
    response = encrypt(json.dumps(document).encode("utf-8"))
    response_bytes = ctypes.string_at(response)
    response_string = response_bytes.decode("utf-8")
    y = json.loads(response_string)
    logger.warning("Received response: %s", y)


def config_wrap_deks(cmd, cleanroom_config, contract_id):
    config = get_cleanroom_config(cleanroom_config)

    if not "kek" in config:
        raise CLIError("Run az cleanroom config set-kek first.")

    cleanroom_config_private = cleanroom_config + ".private"
    with open(cleanroom_config_private, "r") as f:
        private_config = yaml.safe_load(f)

    kek_name = "kek/" + config["kek"]["generateName"] + contract_id
    kek = [pc for pc in private_config if pc["name"] == kek_name]
    if len(kek) == 0:
        raise CLIError(
            "Kek not found. Run 'az cleanroom create-kek' first or pass in "
            + "--governance-client parameter to this command to create the kek automatically."
        )

    if len(kek) > 1:
        raise CLIError(
            f"Found more than one key entry name with name {kek_name}. This is not supported."
        )

    with open(kek[0]["keyFilePath"], "rb") as key_file:
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives import hashes

        private_key = serialization.load_pem_private_key(key_file.read(), password=None)

    public_key = private_key.public_key()

    # Wrap datasources keys
    for ds_entry in config["specification"]["datasources"]:
        ds = ds_entry["datasource"]
        ds_name = ds["Name"]
        dek_name = "datasource/" + ds_name

        dek = [pc for pc in private_config if pc["name"] == dek_name]
        if len(dek) == 0:
            raise CLIError(f"No key for datasource with name '{ds_name}' was found.")
        if len(dek) > 1:
            raise CLIError(
                f"Found more than one key entry name with name '{ds_name}'. This is not supported."
            )

        with open(dek[0]["keyFilePath"], "rb") as key_file:
            dek_bytes = key_file.read()

        ciphertext = base64.b64encode(
            public_key.encrypt(
                dek_bytes,
                padding.OAEP(
                    mgf=padding.MGF1(algorithm=hashes.SHA256()),
                    algorithm=hashes.SHA256(),
                    label=None,
                ),
            )
        ).decode()

        secret_name = ds["Protection"]["EncryptionSecret"]["DEK"]["BackingResource"][
            "Name"
        ]
        vault_url = ds["Protection"]["EncryptionSecret"]["DEK"]["BackingResource"][
            "Provider"
        ]["URL"]
        vault_name = urlparse(vault_url).hostname.split(".")[0]

        logger.warning(
            f"Creating wrapped DEK secret '{secret_name}' for '{dek_name}' in key vault '{vault_name}'."
        )
        az_cli(
            f"keyvault secret set --name {secret_name} --vault-name {vault_name} --value {ciphertext}"
        )

    # Wrap datasink keys
    for ds_entry in config["specification"]["datasinks"]:
        ds = ds_entry["datasink"]
        ds_name = ds["Name"]
        dek_name = "datasink/" + ds_name

        dek = [pc for pc in private_config if pc["name"] == dek_name]
        if len(dek) == 0:
            raise CLIError(f"No key for datasink with name '{ds_name}' was found.")
        if len(dek) > 1:
            raise CLIError(
                f"Found more than one key entry name with name '{ds_name}'. This is not supported."
            )

        with open(dek[0]["keyFilePath"], "rb") as key_file:
            dek_bytes = key_file.read()

        ciphertext = base64.b64encode(
            public_key.encrypt(
                dek_bytes,
                padding.OAEP(
                    mgf=padding.MGF1(algorithm=hashes.SHA256()),
                    algorithm=hashes.SHA256(),
                    label=None,
                ),
            )
        ).decode()

        secret_name = ds["Protection"]["EncryptionSecret"]["DEK"]["BackingResource"][
            "Name"
        ]
        vault_url = ds["Protection"]["EncryptionSecret"]["DEK"]["BackingResource"][
            "Provider"
        ]["URL"]
        vault_name = urlparse(vault_url).hostname.split(".")[0]

        logger.warning(
            f"Creating wrapped DEK secret '{secret_name}' for '{dek_name}' in key vault '{vault_name}'."
        )
        az_cli(
            f"keyvault secret set --name {secret_name} --vault-name {vault_name} --value {ciphertext}"
        )


def create_kek_via_governance(cmd, cleanroom_config, contract_id, gov_client_name):
    cl_policy = governance_deployment_policy_show_cmd(cmd, contract_id, gov_client_name)
    if not "policy" in cl_policy or not "x-ms-sevsnpvm-hostdata" in cl_policy["policy"]:
        raise CLIError(
            f"No clean room policy found under contract '{contract_id}'. Check "
            + "--contract-id parameter is correct and that a policy proposal for the contract has been accepted."
        )

    create_kek(cleanroom_config, contract_id, cl_policy)


def create_kek_with_cl_policy(cmd, cleanroom_config, contract_id, cl_policy):
    if not "policy" in cl_policy or not "x-ms-sevsnpvm-hostdata" in cl_policy["policy"]:
        raise CLIError(
            f"Specify a valid clean room policy for contract '{contract_id}'. Check "
            + "--contract-id parameter is correct and that a policy proposal for the contract has been accepted."
        )

    create_kek(cleanroom_config, contract_id, cl_policy)


def create_kek(cleanroom_config, contract_id, cl_policy):
    key_file_path = get_keys_dir_path(cleanroom_config)
    config = get_cleanroom_config(cleanroom_config)

    if not "kek" in config:
        raise CLIError("Run az cleanroom config set-kek first.")

    if not "policy" in cl_policy or not "x-ms-sevsnpvm-hostdata" in cl_policy["policy"]:
        raise CLIError(
            f"No clean room policy found under contract '{contract_id}'. Check "
            + "--contract-id parameter is correct and that a policy proposal for the contract has been accepted."
        )

    private_config = get_cleanroom_private_config(cleanroom_config)

    name = config["kek"]["generateName"] + contract_id
    pem_file_path = os.path.abspath(os.path.join(key_file_path, f"{name}.pem"))
    if not os.path.exists(pem_file_path):
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization

        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

        unencrypted_pem_private_key = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )
        with open(pem_file_path, "w") as private_key_file:
            private_key_file.write(unencrypted_pem_private_key.decode())

    entry = {"name": "kek/" + name, "keyFilePath": pem_file_path}
    for index, x in enumerate(private_config):
        if x["name"] == entry["name"]:
            private_config[index] = entry
            break
    else:
        private_config.append(entry)

    cce_policy_hash = cl_policy["policy"]["x-ms-sevsnpvm-hostdata"][0]
    authority = config["kek"]["__MAA_URL__"]
    skr_policy = {
        "anyOf": [
            {
                "allOf": [
                    {"claim": "x-ms-sevsnpvm-hostdata", "equals": cce_policy_hash},
                    {
                        "claim": "x-ms-compliance-status",
                        "equals": "azure-compliant-uvm",
                    },
                    {"claim": "x-ms-attestation-type", "equals": "sevsnpvm"},
                ],
                "authority": authority,
            }
        ],
        "version": "1.0.0",
    }

    skr_file_path = os.path.abspath(os.path.join(key_file_path, f"{name}.skr.json"))
    with open(skr_file_path, "w") as f:
        json.dump(skr_policy, f, indent=2)

    url = urlparse(config["kek"]["__HSM_URL__"])
    kv_name = url.hostname.split(".")[0]

    write_cleanroom_private_config(cleanroom_config, private_config)

    vault_param = (
        "--hsm-name"
        if ".managedhsm.azure.net" in config["kek"]["__HSM_URL__"].lower()
        else "--vault-name"
    )
    az_cli(
        f"keyvault key import --name {name} --pem-file {pem_file_path} "
        + f"--policy {skr_file_path} {vault_param} {kv_name} --exportable true "
        + f"--protection hsm --ops encrypt wrapKey --immutable false"
    )


def get_current_jsapp_bundle(cgs_endpoint: str):
    r = requests.get(f"{cgs_endpoint}/jsapp/bundle")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))
    bundle = r.json()
    bundle_hash = hashlib.sha256(bytes(json.dumps(bundle), "utf-8")).hexdigest()
    canonical_bundle = json.dumps(bundle, indent=2, sort_keys=True, ensure_ascii=False)
    canonical_bundle_hash = hashlib.sha256(bytes(canonical_bundle, "utf-8")).hexdigest()
    return bundle, bundle_hash, canonical_bundle, canonical_bundle_hash


def to_canonical_jsapp_bundle(bundle):
    canonical_bundle = json.loads(json.dumps(bundle))
    for key, value in bundle["metadata"]["endpoints"].items():
        # Update the HTTP verb to be in lower case. The case of the verbs in the document hosted
        # in MCR and the verb values reported by CCF's /endpoint api can differ.
        #   "/contracts/{contractId}/oauth/token": { "POST": { =>
        #   "/contracts/{contractId}/oauth/token": { "post": { =>
        for verb, action in value.items():
            del canonical_bundle["metadata"]["endpoints"][key][verb]
            canonical_bundle["metadata"]["endpoints"][key][verb.lower()] = action

    return json.dumps(canonical_bundle, indent=2, sort_keys=True, ensure_ascii=False)


def find_constitution_version_entry(tag: str) -> str | None:
    if tag == "latest":
        return find_version_document_entry("latest", "cgs-constitution")

    version = find_version_manifest_entry(tag, "cgs-constitution")

    if version is not None:
        return version

    # Handle the first release of 1.0.6 and 1.0.7 that went out which does not have version manifest entry.
    if tag == "d1e339962fca8d92fe543617c89bb69127dd075feb3599d8a7c71938a0a6a29f":
        return "1.0.6"

    if tag == "6b5961db2f6c0c9b0a1a640146dceac20e816225b29925891ecbb4b8e0aa9d02":
        return "1.0.8"


def find_jsapp_version_entry(tag: str) -> str | None:
    if tag == "latest":
        return find_version_document_entry("latest", "cgs-js-app")

    version = find_version_manifest_entry(tag, "cgs-js-app")

    if version is not None:
        return version

    # Handle the first release of 1.0.6 and 1.0.7 that went out which does not have version manifest entry.
    if tag == "01043eb27af3faa8f76c1ef3f95e516dcc0b2b78c71302a878ed968da62967b1":
        return "1.0.6"

    if tag == "d42383b4a2d6c88c68cb1114e71da6ad0aa724e90297d1ad82db6206eb6fd417":
        return "1.0.8"


def find_cgs_client_version_entry(tag) -> str | None:
    # Handle the first release of 1.0.6 and 1.0.7 that went out which does not have version document entry.
    if tag == "sha256:6bbdb78ed816cc702249dcecac40467b1d31e5c8cfbb1ef312b7d119dde7024f":
        return "1.0.6"

    if tag == "sha256:38a2c27065a9b6785081eb5e4bf9f3ddd219860d06ad65f5aad4e63466996561":
        return "1.0.7"

    if tag == "sha256:8627a64bb0db303e7a837a06f65e91e1ee9c9d59df1228849c09a59571de9121":
        return "1.0.8"

    return find_version_document_entry(tag, "cgs-client")


def find_version_manifest_entry(tag: str, component: str) -> str | None:
    registry_url = get_versions_registry()
    import oras.client
    import oras.oci

    insecure = False
    if urlparse("https://" + registry_url).hostname == "localhost":
        insecure = True

    if tag.startswith("sha256:"):
        tag = tag[7:]
    component_url = f"{registry_url}/{component}:{tag}"
    client = oras.client.OrasClient(hostname=registry_url, insecure=insecure)
    if not registry_url.startswith(MCR_CLEANROOM_VERSIONS_REGISTRY):
        logger.warning("Fetching the manifest from override url %s", component_url)
    try:
        manifest: dict = client.remote.get_manifest(component_url)
    except Exception as e:
        logger.error(f"Failed to pull manifest: {e}")
        return None

    annotations = manifest.get("annotations", {})
    version = (
        annotations["cleanroom.version"] if "cleanroom.version" in annotations else None
    )
    return version


def find_version_document_entry(tag: str, component: str) -> str | None:
    registry_url = get_versions_registry()
    import oras.client

    insecure = False
    if urlparse("https://" + registry_url).hostname == "localhost":
        insecure = True

    dir_path = os.path.dirname(os.path.realpath(__file__))
    versions_folder = os.path.join(
        dir_path, f"bin{os.path.sep}versions{os.path.sep}{component}"
    )
    if not os.path.exists(versions_folder):
        os.makedirs(versions_folder)

    if tag.startswith("sha256:"):
        tag = tag[7:]
    component_url = f"{registry_url}/versions/{component}:{tag}"
    client = oras.client.OrasClient(hostname=registry_url, insecure=insecure)
    if not registry_url.startswith(MCR_CLEANROOM_VERSIONS_REGISTRY):
        logger.warning(
            "Downloading the version document from override url %s", component_url
        )
    try:
        client.pull(target=component_url, outdir=versions_folder)
    except Exception as e:
        logger.error(f"Failed to pull version document: {e}")
        return None

    versions_file = os.path.join(versions_folder, "version.yaml")
    with open(versions_file) as f:
        versions = yaml.safe_load(f)

    return (
        str(versions[component]["version"])
        if component in versions and "version" in versions[component]
        else None
    )


def constitution_digest_to_version_info(digest):
    cgs_constitution = find_constitution_version_entry(digest)
    if cgs_constitution == None:
        raise CLIError(
            f"Could not identify version for cgs-consitution digest: {digest}. "
            "cleanroom extension upgrade may be required."
        )

    from packaging.version import Version

    upgrade = None
    current_version = Version(cgs_constitution)
    latest_cgs_constitution = find_constitution_version_entry("latest")
    if (
        latest_cgs_constitution != None
        and Version(latest_cgs_constitution) > current_version
    ):
        upgrade = {"constitutionVersion": latest_cgs_constitution}

    return str(current_version), upgrade


def bundle_digest_to_version_info(canonical_digest):
    cgs_jsapp = find_jsapp_version_entry(canonical_digest)
    if cgs_jsapp == None:
        raise CLIError(
            f"Could not identify version for cgs-js-app bundle digest: {canonical_digest}. "
            "cleanroom extension upgrade may be required."
        )

    from packaging.version import Version

    upgrade = None
    current_version = Version(cgs_jsapp)
    latest_cgs_jsapp = find_jsapp_version_entry("latest")
    if latest_cgs_jsapp != None and Version(latest_cgs_jsapp) > current_version:
        upgrade = {"jsappVersion": latest_cgs_jsapp}

    return str(current_version), upgrade


def download_constitution_jsapp(folder, constitution_url="", jsapp_url=""):
    if constitution_url == "":
        constitution_url = os.environ.get(
            "AZCLI_CGS_CONSTITUTION_IMAGE", mcr_cgs_constitution_url
        )
    if jsapp_url == "":
        jsapp_url = os.environ.get("AZCLI_CGS_JSAPP_IMAGE", mcr_cgs_jsapp_url)

    # Extract the registry_hostname from the URL.
    # https://foo.ghcr.io/some:tag => "foo.ghcr.io"
    registry_url = urlparse("https://" + jsapp_url).netloc

    if registry_url != urlparse("https://" + constitution_url).netloc:
        raise CLIError(
            f"Constitution url '{constitution_url}' & js app url '{jsapp_url}' must point to the same registry"
        )

    if constitution_url != mcr_cgs_constitution_url:
        logger.warning(f"Using constitution url override: {constitution_url}")
    if jsapp_url != mcr_cgs_jsapp_url:
        logger.warning(f"Using jsapp url override: {jsapp_url}")

    constitution = download_constitution(folder, constitution_url)
    bundle = download_jsapp(folder, jsapp_url)
    return constitution, bundle


def download_constitution(folder, constitution_url):
    # Extract the registry_hostname the URL.
    # https://foo.ghcr.io/some:tag => "foo.ghcr.io"
    registry_url = urlparse("https://" + constitution_url).netloc

    insecure = False
    if urlparse("https://" + constitution_url).hostname == "localhost":
        insecure = True

    import oras.client

    client = oras.client.OrasClient(hostname=registry_url, insecure=insecure)
    logger.debug("Downloading the constitution from %s", constitution_url)

    try:
        manifest: dict = client.remote.get_manifest(constitution_url)
    except Exception as e:
        raise CLIError(f"Failed to get manifest: {e}")

    layers = manifest.get("layers", [])
    for index, x in enumerate(layers):
        if (
            "annotations" in x
            and "org.opencontainers.image.title" in x["annotations"]
            and x["annotations"]["org.opencontainers.image.title"]
            == "constitution.json"
        ):
            break
    else:
        raise CLIError(
            f"constitution.json document not found in {constitution_url} manifest."
        )

    try:
        client.pull(target=constitution_url, outdir=folder)
    except Exception as e:
        raise CLIError(f"Failed to pull constitution: {e}")

    constitution = json.load(
        open(f"{folder}{os.path.sep}constitution.json", encoding="utf-8", mode="r")
    )
    return constitution


def download_jsapp(folder, jsapp_url):
    # Extract the registry_hostname from one of the URLs.
    # https://foo.ghcr.io/some:tag => "foo.ghcr.io"
    registry_url = urlparse("https://" + jsapp_url).netloc

    insecure = False
    if urlparse("https://" + jsapp_url).hostname == "localhost":
        insecure = True

    import oras.client

    client = oras.client.OrasClient(hostname=registry_url, insecure=insecure)
    logger.debug("Downloading the governance service js application from %s", jsapp_url)

    try:
        manifest: dict = client.remote.get_manifest(jsapp_url)
    except Exception as e:
        raise CLIError(f"Failed to get manifest: {e}")

    layers = manifest.get("layers", [])
    for index, x in enumerate(layers):
        if (
            "annotations" in x
            and "org.opencontainers.image.title" in x["annotations"]
            and x["annotations"]["org.opencontainers.image.title"] == "bundle.json"
        ):
            break
    else:
        raise CLIError(f"bundle.json document not found in {jsapp_url} manifest.")

    try:
        client.pull(target=jsapp_url, outdir=folder)
    except Exception as e:
        raise CLIError(f"Failed to pull js app bundle: {e}")

    bundle = json.load(
        open(f"{folder}{os.path.sep}bundle.json", encoding="utf-8", mode="r")
    )
    return bundle


def get_current_constitution(cgs_endpoint: str):
    r = requests.get(f"{cgs_endpoint}/constitution")
    if r.status_code != 200:
        raise CLIError(response_error_message(r))

    hash = hashlib.sha256(bytes(r.text, "utf-8")).hexdigest()
    return r.text, hash


def get_cgs_client_digest(gov_client_name: str) -> str:
    try:
        import docker

        client = docker.from_env()
        container_name = f"{gov_client_name}-cgs-client-1"
        container = client.containers.get(container_name)
    except Exception as e:
        raise CLIError(
            f"Not finding a client instance running with name '{gov_client_name}'. Check the --name parameter value."
        ) from e

    image = client.images.get(container.image.id)
    repoDigest: str = image.attrs["RepoDigests"][0]
    digest = image.attrs["RepoDigests"][0][len(repoDigest) - 71 :]
    return digest


def get_versions_registry() -> str:
    return os.environ.get(
        "AZCLI_CLEANROOM_VERSIONS_REGISTRY", MCR_CLEANROOM_VERSIONS_REGISTRY
    )


def try_get_constitution_version(digest: str):
    entry = find_constitution_version_entry(digest)
    return "unknown" if entry == None else entry


def try_get_jsapp_version(canonical_digest: str):
    entry = find_jsapp_version_entry(canonical_digest)
    return "unknown" if entry == None else entry


def try_get_cgs_client_version(tag: str):
    entry = find_cgs_client_version_entry(tag)
    return "unknown" if entry == None else entry


def validate_config(config):
    portProperties = []
    issues = []
    for item in config["specification"]["applications"]:
        application = item["application"]
        if len(application["ports"]) > 0:
            for port in application["ports"]:
                portProperties.append({"port": f"{port}", "protocol": "TCP"})
    if len(portProperties) > 0 and "networkPolicy" not in config:
        issues.append(
            {
                "code": "NetworkPolicyMissing",
                "message": "Application(s) open ports but network policy configuration is missing. "
                + "Set the policy via 'config set-network-policy' command",
            }
        )

    seen = set()
    dupes = [
        x["port"] for x in portProperties if x["port"] in seen or seen.add(x["port"])
    ]
    if len(dupes) > 0:
        issues.append(
            {
                "code": "DuplicatePort",
                "message": f"Port {dupes} appear more than once in the application(s). "
                + "A port value can be used only once.",
            }
        )

    if len(issues) > 0:
        raise CLIError(issues)
