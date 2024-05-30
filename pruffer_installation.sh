#!/bin/bash

FILE_PATH=$HOME/pruffer

sudo apt update
sudo apt install -y build-essential curl libssl-dev pkg-config screen

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

rustc --version

mkdir -p $FILE_PATH
cd $FILE_PATH

setup_coral() {
    git clone https://github.com/PufferFinance/coral
    cd coral

    cargo build --release

    echo "Enter your password for the validator keys (it will not be displayed):"
    read -s validator_password
    echo "$validator_password" > password.txt

    echo "Please visit https://launchpad.puffer.fi/Setup to get your command to create your validator key."
    echo "Follow the instructions on the website to connect your Metamask and get the command."
    echo "Modify the command to replace <PATH_TO_A_KEYSTORE_PASSWORD_FILE> with password.txt and <PATH_TO_REGISTRATION_JSON> with registration.json."
    echo "Once you have the modified command, paste it here and press Enter to execute it."

    read user_command
    eval $user_command
}

if [ ! -d "$FILE_PATH/coral" ]; then
    echo "It seems you have not setup the coral directory yet."
    echo "Do you want to setup the coral directory now?If this directory already exists, type NO and provide the correct full_path to it (y/n)"
    read setup_choice

    if [ "$setup_choice" == "y" ]; then
        cd $FILE_PATH
        setup_coral
    else
        echo "Please provide the path to your existing coral directory:"
        read coral_path

        if [ -d "$coral_path" ]; then
            mv "$coral_path" $FILE_PATH/coral
            echo "Coral directory has been moved to $FILE_PATH/coral."
        else
            echo "The provided path does not exist. Exiting setup."
            exit 1
        fi
    fi
else
    echo "Coral directory already exists at $FILE_PATH/coral."
fi

cd ~

sudo apt-get install -y build-essential git-lfs cmake
openssl rand -hex 32 | tr -d "\n" > "/tmp/jwtsecret"
cd ~

if [ ! -d "$HOME/nimbus-eth2" ]; then
    git clone https://github.com/status-im/nimbus-eth2
fi
cd nimbus-eth2

if [ ! -f build/nimbus_beacon_node ]; then
    echo "Enter the amount of RAM you want to dedicate (e.g., 12 for 12GB):"
    read ram_amount

    if [ -z "$ram_amount" ]; then
      make nimbus_beacon_node
    else
      make -j$ram_amount nimbus_beacon_node
    fi
fi

build/nimbus_beacon_node trustedNodeSync \
  --network:holesky \
  --data-dir=build/data/shared_holesky_0 \
  --trusted-node-url=https://holesky-checkpoint-sync.stakely.io/

cd $FILE_PATH/coral/etc/keys/bls_keys
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

cp -v $FILE_PATH/coral/etc/keys/bls_keys/$validator_key_file ~/nimbus-eth2/build/data/shared_holesky_0/validators/

mkdir -p ~/nimbus-eth2/validator_keys/
cp -v $FILE_PATH/coral/etc/keys/bls_keys/$validator_key_file ~/nimbus-eth2/validator_keys/keystore.json

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

cd ~
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y dotnet-sdk-8.0 dotnet-runtime-8.0

dotnet --list-sdks
dotnet --list-runtimes

git clone https://github.com/NethermindEth/nethermind.git
cd nethermind/src/Nethermind/
dotnet build Nethermind.sln -c Release

echo "Enter your wallet address:"
read wallet_address

screen -dmS consensus bash -c "
cd ~/nimbus-eth2
./run-holesky-beacon-node.sh --web3-url=http://127.0.0.1:8551 --suggested-fee-recipient=$wallet_address --jwt-secret=/tmp/jwtsecret
"

if screen -list | grep -q "consensus"; then
  echo "Consensus client is running in a screen session named 'consensus'."
else
  echo "Failed to start consensus client."
fi

screen -dmS execution bash -c "
cd ~/nethermind/src/Nethermind/Nethermind.Runner
dotnet run -c Release -- --config=holesky --datadir=\"../../../../nethermind-datadir\" --JsonRpc.Host=0.0.0.0 --JsonRpc.JwtSecretFile=/tmp/jwtsecret
"

if screen -list | grep -q "execution"; then
  echo "Execution client is running in a screen session named 'execution'."
else
  echo "Failed to start execution client."
fi

echo "Both clients are now running in their respective screen sessions."
echo "You can attach to the sessions using 'screen -r consensus' and 'screen -r execution'."
