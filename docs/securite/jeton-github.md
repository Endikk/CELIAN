# Jeton GitHub des sessions d'agents

Procédure tenue par [SECU]. Elle répond au risque R-07 de
[docs/risques.md](../risques.md) : un agent qui a le shell peut afficher le
jeton de `gh` puis l'envoyer dehors. On ne peut pas empêcher qu'un agent lise le
jeton qu'il utilise. On peut en revanche réduire ce que ce jeton permet.

Faits vérifiés le 15/11/2026 sur la documentation GitHub :

- un jeton à grain fin (fine-grained) se limite à un propriétaire et à une
  liste de dépôts choisis
  (<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens>) ;
- modifier les réglages du dépôt (`PATCH /repos/{owner}/{repo}`) et écrire un
  ruleset demandent la permission Administration en écriture
  (<https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens>) ;
- l'API Checks n'accepte pas les jetons à grain fin (même page des jetons,
  section des limites connues) ;
- `GH_TOKEN` passe devant les identifiants enregistrés par `gh`, et le manuel de
  `gh` conseille cette variable pour un jeton à grain fin
  (<https://cli.github.com/manual/gh_help_environment>,
  <https://cli.github.com/manual/gh_auth_login>).

## Le jeton du quotidien

À créer dans GitHub, Settings, Developer settings, Personal access tokens,
Fine-grained tokens.

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Resource owner | `Endikk` | Le seul propriétaire du dépôt |
| Expiration | 90 jours | Une fuite non détectée finit par expirer |
| Repository access | Only select repositories : `Endikk/CELIAN`, plus les autres dépôts personnels confiés à des agents | Le reste du compte reste hors d'atteinte |
| Contents | Read and write | Pousser des branches |
| Pull requests | Read and write | Ouvrir et commenter les PR |
| Workflows | Read and write | Modifier `.github/workflows/` |
| Actions | Read-only | Lire les exécutions de la CI |
| Commit statuses | Read-only | Lire l'état des checks d'une PR |
| Administration | No access | Le cœur de la mesure : ni réglages, ni ruleset, ni suppression |

Toute autre permission reste sur No access.

## Le brancher

Suivre l'ordre : l'ancien jeton se retire avant que `GH_TOKEN` soit défini,
pour que `gh auth logout` vise bien l'identifiant enregistré.

1. Ranger le jeton dans le trousseau macOS, jamais dans un fichier :

   ```sh
   security add-generic-password -a "$USER" -s gh-agents-token -w
   ```

   La commande demande le jeton sans l'afficher.

2. Dans un shell où `GH_TOKEN` n'est pas défini, retirer l'ancien jeton de
   `gh` : `gh auth logout`. Sans cette étape, il reste dans le trousseau et un
   agent peut le relire en contournant `GH_TOKEN`.

3. Exporter le nouveau jeton dans `~/.zshrc`, puis ouvrir un nouveau shell et
   relancer VS Code pour que Claude Code en hérite :

   ```sh
   export GH_TOKEN="$(security find-generic-password -a "$USER" -s gh-agents-token -w 2>/dev/null)"
   ```

4. Faire passer `git` par `gh`, pour n'avoir qu'un identifiant :
   `gh auth setup-git`.

5. Vérifier : `gh auth status` doit indiquer que le jeton vient de `GH_TOKEN`, puis une branche de
   test doit se pousser et s'ouvrir en PR.

6. Supprimer l'entrée `github.com` que l'assistant `osxkeychain` de `git` avait
   enregistrée dans le trousseau (application Trousseaux d'accès).

7. Révoquer l'ancien jeton classique sur GitHub, dans Settings, Developer
   settings, Tokens (classic). La déconnexion locale ne l'invalide pas : s'il a
   déjà fuité, seule la révocation le rend inutilisable. Vérifier avant qu'aucun
   autre outil ou secret de CI ne s'en sert.

## Les tâches d'administration

`scripts/github/apply-settings.sh` et l'application du ruleset demandent
Administration en écriture. Lucas les lance lui-même, hors session d'agent,
avec un jeton temporaire saisi sans écho, pour qu'il n'entre pas dans
l'historique du shell :

```sh
read -rs ADMIN_TOKEN && GH_TOKEN="$ADMIN_TOKEN" scripts/github/apply-settings.sh; unset ADMIN_TOKEN
```

Le jeton temporaire se crée avec une expiration courte et se révoque après
usage.

## Ce qui reste à vérifier après la bascule

- `gh pr checks` : l'API Checks refuse les jetons à grain fin. Si la commande
  échoue, `gh run list` (permission Actions) donne l'état de la CI.
- `gh auth setup-git` avec `GH_TOKEN` : le push doit utiliser le jeton à grain
  fin. Le constater à l'étape 5, avant de supprimer l'ancien identifiant.
- Un dépôt d'organisation demande son propre jeton : un jeton à grain fin ne
  couvre qu'un seul propriétaire.
