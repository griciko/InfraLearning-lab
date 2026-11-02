# Git — Learning block (about 1 hour)
## 1. What version control actually is

Git tracks changes to your files over time. Instead of `document_final_v2_REALLY_FINAL.docx`, you get a clean history: every change is a commit, with a message, an author, and a timestamp. You can always go back, compare, or undo.

### Three levels to know:

- **Working directory** — the files you're actively editing
- **Staging area** (the "index") — changes you've marked to be included in the next commit
- **Repository** (.git folder) — the permanent history of committed snapshots

## 2. Core commands you'll use today

| Command | What it does |
| ------- | ------------ |
| `git init` | Turn a folder into a Git repo |
| `git status` | See what's changed / staged |
| `git add <file>` | Stage a file |
| `git commit -m "message"` | Save a snapshot |
| `git log --oneline` | See history, compact |
| `git branch` | List / create branches |
| `git checkout -b <name> or git switch -c <name>` | Create and move to a new branch |
| `git merge <branch>` | Bring a branch's changes into the current one |
| `git clone <url>` |Copy a remote repo locally |
| `git remote -v` | Show connected remotes |
| `git push / git pull` | Send / receive commits to/from a remote |

## 3. Branches, in one sentence

A branch is a movable pointer to a commit. main is just the default branch name — creating a new branch costs nothing and lets you experiment without touching working code. This is why Git workflows are built around "branch, change, merge" instead of editing main directly.

## 4. Merge conflicts, in one sentence

A conflict happens when Git can't automatically combine two changes to the same lines of a file. Git pauses and asks you to pick the result by hand — it's not an error, it's a normal part of collaborating.

# Git — Lab (about 2 hours)

We'll go step by step. Run each command, check the output, then move to the next. Ask if anything looks unexpected.

## **Step 1** — Set up your identity (one-time only)

Open PowerShell and run:

```
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
git config --global init.defaultBranch main
```

Verify:
```
git config --global --list
```

## **Step 2** — Create the local folder and initialize Git
cd ~
mkdir infra-learning-lab
cd infra-learning-lab
git init

Move your downloaded README.md and .gitignore into this folder now.

Check status:
git status
You should see both files listed as untracked.

Step 3 — Your first commit
git add README.md .gitignore
git status

Notice the files are now staged (green, "Changes to be committed"). Now commit:
git commit -m "Initial commit: add README and gitignore"

View it:
git log --oneline

Step 4 — Create the folder structure
mkdir 01-git, 02-terraform-local, 03-cicd, 04-ansible, 05-powershell, docs

New-Item 01-git/README.md, 02-terraform-local/README.md, 03-cicd/README.md, 04-ansible/README.md, 05-powershell/README.md, docs/notes-and-lessons.md -ItemType File

Add a one-line placeholder in each (e.g. # Git in 01-git/README.md) so they're not empty — open them in VS Code, it's faster.

Stage and commit:
git add .
git commit -m "Add folder structure for learning topics"

Step 5 — Connect to GitHub and push

On GitHub, copy your repo's URL (HTTPS is simplest to start). Then:
git remote add origin https://github.com/<your-username>/infra-learning-lab.git
git remote -v
git branch -M main
git push -u origin main

You'll be prompted to authenticate — GitHub will likely open a browser sign-in.
Refresh the repo page on GitHub. You should see your files.