#!/bin/bash
# Example arguments for parliament.pl
perl parliament.pl lacuna.yml --station "Station One" --station "Station Two" --id_station 42 \
--pass '^install' --pass '^upgrade' --pass '^demolish dent' \
--pass '^seize' --pass '^rename' --pass '^repair' --pass '^transfer' \
--pass '^fire'  --pass '^neutral' --pass '^fire' --pass '^repeal'
# Will only look at stations "Station One", "Station Two", and a station with the body id of 42
# and pass practically everything.
