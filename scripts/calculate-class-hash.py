import os
import json
from starkware.starknet.core.os.class_hash import compute_class_hash
from starkware.starknet.services.api.contract_class import ContractClass

path_to_json = './artifacts/'
json_files = [pos_json for pos_json in os.listdir(
    path_to_json) if pos_json.endswith('.json')]


def print_class_hash(class_location):
    location = path_to_json + class_location
    with open(location) as f:
        class_data = json.load(f)
    contract_class = ContractClass.load(class_data)
    contract_hash = compute_class_hash(
        contract_class=contract_class,
    )
    print("{} class hash: {}".format(class_location, hex(contract_hash)))


list(map(print_class_hash, json_files))
