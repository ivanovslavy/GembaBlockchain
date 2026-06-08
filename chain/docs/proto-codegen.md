# Proto codegen (regenerating `*.pb.go`)

The Gemba Go modules use protobuf-generated types. Generated files (`x/*/types/*.pb.go`) are
committed, so a normal `go build` needs **no** proto toolchain. You only need the toolchain when
you change a `.proto` file.

## One-time toolchain setup

```bash
# buf + the gogo/cosmos protoc plugin (versions: buf 1.47.x; gocosmos = the cosmos/gogoproto
# version pinned in chain/go.mod — `grep cosmos/gogoproto go.mod`)
go install github.com/bufbuild/buf/cmd/buf@v1.47.2
go install github.com/cosmos/gogoproto/protoc-gen-gocosmos@v1.7.2   # match go.mod
export PATH="$HOME/go/bin:$PATH"
```

`buf generate` resolves the proto deps (cosmos-sdk, cosmos-proto, gogo-proto, googleapis) from
the Buf Schema Registry per `proto/buf.lock` — needs network to `buf.build`.

## Regenerate

```bash
cd chain/proto
buf generate --template buf.gen.gogo.yaml          # writes to proto/out/<go_package path>/
# copy the generated files into each module's types dir, e.g.:
OUT=out/github.com/ivanovslavy/GembaBlockchain/chain/x
for m in feesplit rewardstreamer tailreward valgate; do
  cp "$OUT/$m/types/"*.pb.go "../x/$m/types/"
done
rm -rf out
cd .. && go build ./... && go test ./x/...
```

> `proto/out/` is a scratch dir (gitignored) — only the copied `x/*/types/*.pb.go` are committed.

## Module Msg/params layout (the MsgUpdateParams pattern)

Each governance-tunable module has:
- `proto/gemba/<mod>/v1/params.proto` — the `Params` message (the gov-tunable params).
- `proto/gemba/<mod>/v1/tx.proto` — `Msg.UpdateParams(MsgUpdateParams) → MsgUpdateParamsResponse`.
- `x/<mod>/types/{params,tx}.pb.go` — generated.
- `x/<mod>/types/params.go` — `DefaultParams()` + `Validate()` helpers on the generated `Params`.
- `x/<mod>/types/codec.go` — `RegisterInterfaces` (registers `MsgUpdateParams`).
- `x/<mod>/keeper/msg_server.go` — `UpdateParams`; authority = the gov module account
  (`authtypes.NewModuleAddress(govtypes.ModuleName)`), checked before `SetParams`.
- `x/<mod>/module.go` — `RegisterServices` (registers the Msg server) + `RegisterInterfaces`.

`valgate`, `feesplit`, `rewardstreamer`, `tailreward` all follow this — so governance can tune the
self-bond floor, the 60/40 fee split, the reserve reward stream, and the §16.8/ADR-008 tail reward
**on-chain via `MsgUpdateParams`, no chain restart** (audit finding #5, fixed 2026-06-08).
