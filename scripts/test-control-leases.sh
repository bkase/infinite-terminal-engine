#!/bin/sh
set -eu

exec ./Scripts/swiftpm-cache.sh test --filter 'RoomActorTests|RoomGatewayTests|SessionTransportTests|RoomFormalModelTests'
