cd ~/puffer/coral/etc/keys/bls_keys
validator_keys=( $(ls) )

echo "Select a validator key file from the list below:"
select validator_key_file in "${validator_keys[@]}"; do
    if [ -n "$validator_key_file" ]; then
        echo "You selected $validator_key_file"
        break
    else
        echo "Invalid selection, please try again."
    fi
done

cp -v ~/puffer/coral/etc/keys/bls_keys/$validator_key_file ~/nimbus-eth2/build/data/shared_holesky_0/validators/

mkdir -p ~/nimbus-eth2/validator_keys/
cp -v ~/puffer/coral/etc/keys/bls_keys/$validator_key_file ~/nimbus-eth2/validator_keys/keystore.json

cd ~/nimbus-eth2/
while true; do
    echo "Enter the password you used when creating the puffer validator key:"
    read -s validator_password
    output=$(echo $validator_password | build/nimbus_beacon_node deposits import --data-dir=build/data/shared_holesky_0 2>&1)
    echo "$output"
    if [[ "$output" == *"System error while entering password"* ]]; then
        echo "Invalid password. Please try again."
        continue
    elif [[ "$output" == *"Failed to import keystore"* || "$output" == *"press ENTER to skip importing this keystore"* ]]; then
        echo "Failed to import keystore."
        echo "Try importing the keys again? (y/n)"
        read try_again
        if [[ "$try_again" == "y" || "$try_again" == "yes" ]]; then
            continue
        fi
    else
        continue
    fi
    break
done
