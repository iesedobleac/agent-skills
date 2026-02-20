---
name: skills-publisher
description: Publica en GitHub las skills indicadas y regenera automaticamente un README profesional con categorias, iconos y tabla de skills.
metadata:
  short-description: Publicar skills privadas con README visual
---

# Skills Publisher

Usa esta skill cuando el usuario quiera subir skills concretas a su repositorio GitHub y mantener un `README.md` cuidado y actualizado.

## Objetivo

- Subir solo las skills que indique el usuario.
- Eliminar skills del repo destino cuando el usuario lo pida.
- Mantener estructura en el repo:
  - `.codex/skills/<skill-name>/...`
  - `.codex/skills-catalog.json`
  - `README.md`
- `CHANGELOG.md`
- Regenerar `README.md` con una vista visual por categorias e iconos.

## Flujo

1. Confirmar repo destino (ej. `owner/private-skills`).
2. Confirmar lista de skills a publicar y categoria opcional por skill.
3. Ejecutar `scripts/publish_skills_to_repo.sh`.
4. Mostrar resultado final (skills publicadas, rutas y enlace repo).

## Confirmaciones obligatorias

- Antes de publicar en remoto, pedir confirmacion explicita.
- Si una skill no existe localmente, parar y pedir decision.

## Script principal

```bash
scripts/publish_skills_to_repo.sh \
  --repo owner/private-skills \
  --skill committer:Oysho-Training \
  --skill pr-review-es:Oysho-Training \
  --yes

scripts/publish_skills_to_repo.sh \
  --repo owner/private-skills \
  --remove-skill old-skill \
  --yes
```

## Notas de uso

- Categoria es opcional (`--skill nombre`), por defecto `General`.
- Categorias comunes se normalizan automaticamente (`oysho`, `review`, `automation`, etc.).
- El script extrae la descripcion desde el frontmatter de cada `SKILL.md`.
- El README se regenera en cada ejecucion con todo el catalogo.
- El CHANGELOG se actualiza en cada publicacion.
- `--skills-root` permite usar una ruta local distinta para buscar skills.
- Si no usas `--yes`, pide confirmacion interactiva antes de publicar.
- `--remove-skill <nombre>` elimina la skill del repo remoto y del catalogo.
