git clone <repo_url>
cd <repo_name>

for branch in $(git branch -r | sed 's/origin\///' | grep -v HEAD); do
  git checkout "$branch" >/dev/null 2>&1
  if grep -R "your_search_string" . >/dev/null 2>&1; then
    echo "Found in branch: $branch"
  fi
done
