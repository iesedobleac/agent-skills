#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Uso:
  publish_skills_to_repo.sh --repo <owner/repo> [--skill <nombre[:categoria]> ...] [--remove-skill <nombre> ...] [--skills-root <ruta>] [--yes]

Ejemplos:
  publish_skills_to_repo.sh --repo iesedobleac/private-skills --skill committer:Oysho-Training --skill pr-review-es:Code-Review --yes
  publish_skills_to_repo.sh --repo iesedobleac/private-skills --skill committer
  publish_skills_to_repo.sh --repo iesedobleac/private-skills --remove-skill committer --yes
USAGE
}

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh no esta instalado o no esta en PATH." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq no esta instalado o no esta en PATH." >&2
  exit 1
fi

repo=""
skills_root="/Users/isaac/.codex/skills"
assume_yes="no"
declare -a skills_raw=()
declare -a remove_skills=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "ERROR: falta valor para --repo" >&2; exit 1; }
      repo="$2"
      shift 2
      ;;
    --skill)
      [[ $# -ge 2 ]] || { echo "ERROR: falta valor para --skill" >&2; exit 1; }
      skills_raw+=("$2")
      shift 2
      ;;
    --remove-skill)
      [[ $# -ge 2 ]] || { echo "ERROR: falta valor para --remove-skill" >&2; exit 1; }
      remove_skills+=("$2")
      shift 2
      ;;
    --skills-root)
      [[ $# -ge 2 ]] || { echo "ERROR: falta valor para --skills-root" >&2; exit 1; }
      skills_root="$2"
      shift 2
      ;;
    --yes)
      assume_yes="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: argumento no reconocido: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$repo" ]] || { echo "ERROR: debes indicar --repo" >&2; exit 1; }
if [[ ${#skills_raw[@]} -eq 0 && ${#remove_skills[@]} -eq 0 ]]; then
  echo "ERROR: debes indicar al menos un --skill o --remove-skill" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
catalog_file="$workdir/skills-catalog.json"
readme_file="$workdir/README.md"
changelog_file="$workdir/CHANGELOG.md"

repo_is_private="$(gh api "repos/$repo" --jq '.private')"
if [[ "$repo_is_private" == "true" ]]; then
  readme_title="Private Skills Vault"
  readme_tagline="Repositorio privado para skills de trabajo y uso personal."
  visibility_badge="![Visibility](https://img.shields.io/badge/visibility-private-black)"
  visibility_label="Privado"
else
  readme_title="Agent Skills"
  readme_tagline="Repositorio publico de skills para agentes."
  visibility_badge="![Visibility](https://img.shields.io/badge/visibility-public-brightgreen)"
  visibility_label="Publico"
fi

# Carga catalogo actual (si existe)
if gh api "repos/$repo/contents/.codex/skills-catalog.json" --jq .content >/dev/null 2>&1; then
  gh api "repos/$repo/contents/.codex/skills-catalog.json" --jq .content | tr -d '\n' | base64 --decode > "$catalog_file"
else
  printf '{"skills":[]}\n' > "$catalog_file"
fi

if gh api "repos/$repo/contents/CHANGELOG.md" --jq .content >/dev/null 2>&1; then
  gh api "repos/$repo/contents/CHANGELOG.md" --jq .content | tr -d '\n' | base64 --decode > "$changelog_file"
else
  printf '# Changelog\n\n' > "$changelog_file"
fi

upload_file() {
  local src="$1"
  local dst="$2"
  local message="$3"
  local content sha

  content="$(base64 < "$src" | tr -d '\n')"
  sha="$(gh api "repos/$repo/contents/$dst" --jq .sha 2>/dev/null || true)"

  if [[ -n "$sha" ]]; then
    gh api "repos/$repo/contents/$dst" -X PUT -f message="$message" -f content="$content" -f sha="$sha" >/dev/null
  else
    gh api "repos/$repo/contents/$dst" -X PUT -f message="$message" -f content="$content" >/dev/null
  fi
}

delete_file_remote() {
  local dst="$1"
  local message="$2"
  local sha
  sha="$(gh api "repos/$repo/contents/$dst" --jq .sha 2>/dev/null || true)"
  if [[ -n "$sha" ]]; then
    gh api "repos/$repo/contents/$dst" -X DELETE -f message="$message" -f sha="$sha" >/dev/null
  fi
}

extract_description() {
  local skill_md="$1"
  awk '
    /^description:/ {
      sub(/^description:[[:space:]]*/, "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$skill_md"
}

category_icon() {
  local category="$1"
  local category_lc
  category_lc="$(printf '%s' "$category" | tr '[:upper:]' '[:lower:]')"
  case "$category_lc" in
    *oysho*|*android*|*mobile*) echo "🏋️" ;;
    *review*|*qa*|*quality*) echo "🔍" ;;
    *git*|*commit*|*devops*) echo "🧾" ;;
    *automation*|*ops*) echo "⚙️" ;;
    *) echo "🧩" ;;
  esac
}

normalize_category() {
  local category="$1"
  local category_lc
  category_lc="$(printf '%s' "$category" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')"
  case "$category_lc" in
    oysho-training|oysho*|android-mobile) echo "Oysho-Training" ;;
    code-review|review|qa|quality) echo "Code-Review" ;;
    automation|ops|devops) echo "Automation" ;;
    general|"") echo "General" ;;
    *)
      # Respeta categorias personalizadas, limpiando espacios exteriores.
      printf '%s' "$category" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
      ;;
  esac
}

if [[ "$assume_yes" != "yes" ]]; then
  if [[ -t 0 ]]; then
    echo "Se publicaran cambios en $repo:"
    if [[ ${#skills_raw[@]} -gt 0 ]]; then
      echo "Skills a publicar/actualizar:"
      printf ' - %s\n' "${skills_raw[@]}"
    fi
    if [[ ${#remove_skills[@]} -gt 0 ]]; then
      echo "Skills a eliminar:"
      printf ' - %s\n' "${remove_skills[@]}"
    fi
    printf 'Continuar? [y/N]: '
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Cancelado por el usuario."
      exit 1
    fi
  else
    echo "ERROR: se requiere confirmacion interactiva. Usa --yes para ejecucion no interactiva." >&2
    exit 1
  fi
fi

# Eliminar skills solicitadas del repo y catalogo
if [[ ${#remove_skills[@]} -gt 0 ]]; then
  tree_file="$workdir/repo-tree-files.txt"
  gh api "repos/$repo/git/trees/HEAD?recursive=1" --jq '.tree[] | select(.type=="blob") | .path' > "$tree_file"

  for skill_to_remove in "${remove_skills[@]}"; do
    prefix=".codex/skills/$skill_to_remove/"
    while IFS= read -r path; do
      [[ "$path" == "$prefix"* ]] || continue
      delete_file_remote "$path" "Remove skill $skill_to_remove ($path)"
    done < "$tree_file"

    tmp_catalog="$workdir/catalog.remove.tmp.json"
    jq --arg n "$skill_to_remove" '
      .skills = ((.skills // []) | map(select(.name != $n)))
    ' "$catalog_file" > "$tmp_catalog"
    mv "$tmp_catalog" "$catalog_file"
  done
fi

for raw in "${skills_raw[@]}"; do
  skill_name="$raw"
  skill_category="General"

  if [[ "$raw" == *:* ]]; then
    skill_name="${raw%%:*}"
    skill_category="${raw#*:}"
    [[ -n "$skill_category" ]] || skill_category="General"
  fi
  skill_category="$(normalize_category "$skill_category")"

  local_skill_dir="$skills_root/$skill_name"
  local_skill_md="$local_skill_dir/SKILL.md"

  if [[ ! -d "$local_skill_dir" || ! -f "$local_skill_md" ]]; then
    echo "ERROR: skill no encontrada en $local_skill_dir" >&2
    exit 1
  fi

  skill_desc="$(extract_description "$local_skill_md")"
  [[ -n "$skill_desc" ]] || skill_desc="(Sin descripcion)"

  while IFS= read -r -d '' file; do
    rel="${file#"$local_skill_dir"/}"
    remote_path=".codex/skills/$skill_name/$rel"
    upload_file "$file" "$remote_path" "Publish skill $skill_name ($rel)"
  done < <(find "$local_skill_dir" -type f -print0)

  updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  icon="$(category_icon "$skill_category")"

  tmp_catalog="$workdir/catalog.tmp.json"
  jq \
    --arg n "$skill_name" \
    --arg c "$skill_category" \
    --arg i "$icon" \
    --arg d "$skill_desc" \
    --arg p ".codex/skills/$skill_name" \
    --arg u "$updated_at" \
    '
      .skills = ((.skills // []) | map(select(.name != $n)))
      | .skills += [{
          name: $n,
          category: $c,
          icon: $i,
          description: $d,
          path: $p,
          updated_at: $u
        }]
      | .skills |= sort_by(.category, .name)
    ' "$catalog_file" > "$tmp_catalog"
  mv "$tmp_catalog" "$catalog_file"

done

# Genera README visual
updated="$(date -u +"%Y-%m-%d %H:%M UTC")"

{
  echo "# $readme_title"
  echo
  echo "> $readme_tagline"
  echo
  echo "$visibility_badge ![Skills](https://img.shields.io/badge/skills-managed-blue)"
  echo
  echo "## Overview"
  echo
  echo "- Repo: \`$repo\`"
  echo "- Visibilidad: \`$visibility_label\`"
  echo "- Ultima actualizacion: \`$updated\`"
  echo
  echo "## Skills by Category"
  echo

  jq -r '
    def esc: gsub("\\|"; "\\\\|") | gsub("`"; "\\\\`") | gsub("\r?\n"; " ");
    (.skills // [])
    | group_by(.category)
    | .[]
    | "### " + (.[0].icon // "🧩") + " " + (.[0].category // "General") + "\n\n"
      + "| Skill | Descripcion | Ruta | Actualizado |\n|---|---|---|---|\n"
      + (map("| `" + (.name|esc) + "` | " + (.description|esc) + " | `" + (.path|esc) + "` | `" + (.updated_at|esc) + "` |") | join("\n"))
      + "\n"
  ' "$catalog_file"

  echo "## Publishing"
  echo
  echo "Este repositorio se mantiene con la skill \`skills-publisher\`."
} > "$readme_file"

# Actualiza CHANGELOG
now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
entry_file="$workdir/changelog-entry.md"
{
  echo "## $now_iso"
  echo
  echo "- Updated skills publication in \`$repo\`."
  if [[ ${#skills_raw[@]} -gt 0 ]]; then
    echo "- Published/updated skills:"
    for raw in "${skills_raw[@]}"; do
      echo "  - \`$raw\`"
    done
  fi
  if [[ ${#remove_skills[@]} -gt 0 ]]; then
    echo "- Removed skills:"
    for removed in "${remove_skills[@]}"; do
      echo "  - \`$removed\`"
    done
  fi
  echo
} > "$entry_file"

if grep -q '^# Changelog' "$changelog_file"; then
  tail_file="$workdir/changelog-tail.md"
  tail -n +2 "$changelog_file" > "$tail_file"
  {
    echo "# Changelog"
    echo
    cat "$entry_file"
    cat "$tail_file"
  } > "$workdir/changelog-new.md"
else
  {
    echo "# Changelog"
    echo
    cat "$entry_file"
    cat "$changelog_file"
  } > "$workdir/changelog-new.md"
fi
mv "$workdir/changelog-new.md" "$changelog_file"

upload_file "$catalog_file" ".codex/skills-catalog.json" "Update skills catalog"
upload_file "$readme_file" "README.md" "Regenerate README"
upload_file "$changelog_file" "CHANGELOG.md" "Update changelog"

echo "Publicacion completada en $repo"
if [[ ${#skills_raw[@]} -gt 0 ]]; then
  echo "Skills publicadas/actualizadas:"
  printf ' - %s\n' "${skills_raw[@]}"
fi
if [[ ${#remove_skills[@]} -gt 0 ]]; then
  echo "Skills eliminadas:"
  printf ' - %s\n' "${remove_skills[@]}"
fi
