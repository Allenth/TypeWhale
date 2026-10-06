#!/usr/bin/env python3
"""Clone verified GPT-OSS weights into TypeWhale's managed model directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import stat
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Artifact:
    name: str
    expected_bytes: int
    sha256: str


@dataclass(frozen=True)
class ModelDescriptor:
    model_id: str
    artifacts: tuple[Artifact, ...]

    @property
    def total_bytes(self) -> int:
        return sum(artifact.expected_bytes for artifact in self.artifacts)


@dataclass(frozen=True)
class BootstrapResult:
    status: str
    model_id: str
    bytes: int
    elapsed_ms: int


class BootstrapError(RuntimeError):
    pass


GPT_OSS_20B = ModelDescriptor(
    model_id="gpt-oss-20b-mxfp4-q8",
    artifacts=(
        Artifact(
            "chat_template.jinja",
            16_738,
            "a4c9919cbbd4acdd51ccffe22da049264b1b73e59055fa58811a99efbd7c8146",
        ),
        Artifact(
            "config.json",
            33_998,
            "d1c1f73bf62116ed0bb37c068af80534543cd1de9b61d609fc01bf70920e842d",
        ),
        Artifact(
            "generation_config.json",
            177,
            "f9970ada892d2d1f72e3ed0a6535ccebadd11897318794ca671d8c7014c957da",
        ),
        Artifact(
            "model-00001-of-00003.safetensors",
            5_303_719_858,
            "57f4846924652b1b23537c6c6d6b65f64fde811e47369d4e23c5c45b4d7584a7",
        ),
        Artifact(
            "model-00002-of-00003.safetensors",
            5_281_581_967,
            "4a862a873080e489db16125877e19553b958562ff4dd0246135bc061c3293652",
        ),
        Artifact(
            "model-00003-of-00003.safetensors",
            1_490_905_743,
            "16c32bb8dbd1fa8d556815706589d6d6480d29946196cd2fe2b721d4daf84132",
        ),
        Artifact(
            "model.safetensors.index.json",
            67_046,
            "6fa724aa7a9130561f9b97debcc06c56ba150d8fbd58fc1168f53a22d6a5490a",
        ),
        Artifact(
            "special_tokens_map.json",
            440,
            "8464cabd6eda239fe46ebf8ae63b46c417721784a961a022f6b59174a2cda0e2",
        ),
        Artifact(
            "tokenizer.json",
            27_868_174,
            "0614fe83cadab421296e664e1f48f4261fa8fef6e03e63bb75c20f38e37d07d3",
        ),
        Artifact(
            "tokenizer_config.json",
            21_694,
            "2d8386578f85ea1fa698e78c58b2d8503e8122d6b110b61f93d3995601b07d91",
        ),
    ),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(4 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def validate(directory: Path, descriptor: ModelDescriptor) -> None:
    if not directory.is_absolute() or not directory.is_dir():
        raise BootstrapError("model_root_invalid")
    for artifact in descriptor.artifacts:
        path = directory / artifact.name
        try:
            file_stat = path.lstat()
        except OSError as error:
            raise BootstrapError("artifact_missing") from error
        if not stat.S_ISREG(file_stat.st_mode) or path.is_symlink():
            raise BootstrapError("artifact_type_invalid")
        if file_stat.st_size != artifact.expected_bytes:
            raise BootstrapError("artifact_size_invalid")
        if _sha256(path) != artifact.sha256:
            raise BootstrapError("artifact_hash_invalid")


def _emit(result: BootstrapResult) -> None:
    print(
        json.dumps(
            {
                "status": result.status,
                "model_id": result.model_id,
                "bytes": result.bytes,
                "elapsed_ms": result.elapsed_ms,
            },
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def bootstrap(
    source: Path,
    destination: Path,
    descriptor: ModelDescriptor = GPT_OSS_20B,
    *,
    replace: bool = False,
) -> BootstrapResult:
    started = time.monotonic()
    source = source.expanduser().resolve()
    destination = destination.expanduser().resolve()
    if source == destination or source in destination.parents:
        raise BootstrapError("source_destination_overlap")
    validate(source, descriptor)

    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = destination.parent / f".installing-{descriptor.model_id}"
    backup = destination.parent / f".backup-{descriptor.model_id}"
    if destination.exists() and not replace:
        raise BootstrapError("destination_exists")

    staging_created = False
    promoted = False
    try:
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        staging_created = True
        subprocess.run(
            ["/bin/cp", "-cR", f"{source}/.", str(staging)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        validate(staging, descriptor)

        if backup.exists():
            shutil.rmtree(backup)
        if destination.exists():
            destination.rename(backup)
        try:
            staging.rename(destination)
            staging_created = False
            promoted = True
            validate(destination, descriptor)
        except BaseException:
            if destination.exists():
                shutil.rmtree(destination)
            if backup.exists():
                backup.rename(destination)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    except BootstrapError:
        raise
    except (OSError, subprocess.SubprocessError) as error:
        raise BootstrapError("clone_failed") from error
    finally:
        if staging_created and staging.exists():
            shutil.rmtree(staging)
        if not promoted and backup.exists() and not destination.exists():
            backup.rename(destination)

    result = BootstrapResult(
        status="ready",
        model_id=descriptor.model_id,
        bytes=descriptor.total_bytes,
        elapsed_ms=round((time.monotonic() - started) * 1_000),
    )
    _emit(result)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--replace", action="store_true")
    return parser.parse_args()


def main() -> int:
    started = time.monotonic()
    args = parse_args()
    try:
        bootstrap(
            args.source,
            args.destination,
            GPT_OSS_20B,
            replace=args.replace,
        )
        return 0
    except BootstrapError as error:
        _emit(
            BootstrapResult(
                status=f"error:{error}",
                model_id=GPT_OSS_20B.model_id,
                bytes=0,
                elapsed_ms=round((time.monotonic() - started) * 1_000),
            )
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
