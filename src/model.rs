use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use chrono::{DateTime, Utc};

const CONTENT_LIMIT_BYTES: u64 = 512 * 1024;
const LIVE_TAIL_LIMIT_BYTES: u64 = 64 * 1024;

#[derive(Clone, Debug, Default)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub state: String,
    pub lane: String,
    pub model: String,
    pub mode: String,
    pub pid: u32,
    pub controller: PathBuf,
    pub started_at: String,
    pub updated_at: String,
    pub cwd: PathBuf,
    pub log: PathBuf,
    pub result: PathBuf,
    pub exit_code: String,
    pub message: String,
    pub state_dir: PathBuf,
}

impl Task {
    pub fn is_active(&self) -> bool {
        matches!(self.state.as_str(), "starting" | "running")
    }

    pub fn display_title(&self) -> &str {
        if self.title.is_empty() {
            &self.id
        } else {
            &self.title
        }
    }

    pub fn model_display(&self) -> &str {
        if self.model.is_empty() {
            "default"
        } else {
            &self.model
        }
    }

    pub fn workspace_name(&self) -> String {
        self.cwd
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.is_empty())
            .unwrap_or("/")
            .to_owned()
    }

    pub fn elapsed_label(&self) -> String {
        let Some(start) = parse_time(&self.started_at) else {
            return "--".to_owned();
        };
        let end = if self.is_active() {
            Utc::now()
        } else {
            parse_time(&self.updated_at).unwrap_or_else(Utc::now)
        };
        format_duration((end - start).num_seconds().max(0))
    }

    fn sort_time(&self) -> i64 {
        parse_time(&self.updated_at)
            .or_else(|| parse_time(&self.started_at))
            .map(|value| value.timestamp())
            .unwrap_or_default()
    }
}

pub fn state_root() -> PathBuf {
    if let Some(path) = std::env::var_os("CODEX_ORCHESTRATOR_STATE_ROOT") {
        return PathBuf::from(path);
    }
    std::env::temp_dir().join("codex-orchestrator")
}

pub fn discover_tasks(root: &Path) -> Result<Vec<Task>> {
    if !root.exists() {
        return Ok(Vec::new());
    }

    let process_commands = lane_process_commands();
    let mut tasks = Vec::new();
    for entry in fs::read_dir(root).with_context(|| format!("read {}", root.display()))? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let state_dir = entry.path();
        let state_file = state_dir.join("state");
        if !state_file.is_file() {
            continue;
        }
        match parse_task(&state_file, &state_dir) {
            Ok(mut task) => {
                refresh_task_state(&mut task, process_commands.as_ref());
                tasks.push(task);
            }
            Err(error) => eprintln!("skip {}: {error:#}", state_file.display()),
        }
    }

    tasks.sort_by(|left, right| {
        right
            .is_active()
            .cmp(&left.is_active())
            .then_with(|| right.sort_time().cmp(&left.sort_time()))
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(tasks)
}

pub fn find_task<'a>(tasks: &'a [Task], id: &str) -> Result<&'a Task> {
    if let Some(task) = tasks.iter().find(|task| task.id == id) {
        return Ok(task);
    }
    let matches: Vec<&Task> = tasks
        .iter()
        .filter(|task| task.id.starts_with(id))
        .collect();
    match matches.as_slice() {
        [task] => Ok(*task),
        [] => bail!("task not found: {id}"),
        _ => bail!("task id is ambiguous: {id}"),
    }
}

pub fn read_task_content(task: &Task, result: bool) -> Result<Vec<String>> {
    let path = if result { &task.result } else { &task.log };
    read_task_path(task, path, CONTENT_LIMIT_BYTES)
}

pub fn read_task_live_tail(task: &Task) -> Result<Vec<String>> {
    read_task_path(task, &task.log, LIVE_TAIL_LIMIT_BYTES)
}

fn read_task_path(task: &Task, path: &Path, limit: u64) -> Result<Vec<String>> {
    if !path.is_file() {
        return Ok(vec![format!("Waiting for {}", path.display())]);
    }

    let bytes = read_tail(path, limit).with_context(|| format!("read {}", path.display()))?;
    let clean = strip_ansi_escapes::strip(bytes);
    let text = String::from_utf8_lossy(&clean);
    let mut lines: Vec<String> = text.lines().map(ToOwned::to_owned).collect();
    if lines.is_empty() {
        lines.push(if task.is_active() {
            "Quiet - waiting for agent output".to_owned()
        } else {
            "No output was captured".to_owned()
        });
    }
    Ok(lines)
}

pub fn stop_task(task: &Task) -> Result<String> {
    if task.controller.as_os_str().is_empty() {
        bail!("task {} does not record a supervisor controller", task.id);
    }
    let output = Command::new(&task.controller)
        .arg("stop")
        .arg("--state-dir")
        .arg(&task.state_dir)
        .output()
        .with_context(|| format!("run {} stop", task.controller.display()))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        bail!("stop failed: {}{}", stdout, stderr);
    }
    Ok(format!("{stdout}{stderr}"))
}

fn parse_task(state_file: &Path, state_dir: &Path) -> Result<Task> {
    let text = fs::read_to_string(state_file)
        .with_context(|| format!("read state {}", state_file.display()))?;
    let fields: HashMap<&str, &str> = text
        .lines()
        .filter_map(|line| line.split_once('='))
        .collect();
    let path_field = |name: &str, default_name: &str| {
        fields
            .get(name)
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| state_dir.join(default_name))
    };
    let id = fields
        .get("task_id")
        .filter(|value| !value.is_empty())
        .map(|value| (*value).to_owned())
        .or_else(|| {
            state_dir
                .file_name()
                .and_then(|name| name.to_str())
                .map(ToOwned::to_owned)
        })
        .context("state directory has no task id")?;

    Ok(Task {
        id,
        title: field(&fields, "title"),
        state: field(&fields, "state"),
        lane: field(&fields, "lane"),
        model: field(&fields, "model"),
        mode: field(&fields, "mode"),
        pid: field(&fields, "pid").parse().unwrap_or_default(),
        controller: fields
            .get("controller")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_default(),
        started_at: field(&fields, "started_at"),
        updated_at: field(&fields, "updated_at"),
        cwd: path_field("cwd", ""),
        log: path_field("log", "lane.log"),
        result: path_field("result", "result.txt"),
        exit_code: field(&fields, "exit_code"),
        message: field(&fields, "message"),
        state_dir: state_dir.to_owned(),
    })
}

fn field(fields: &HashMap<&str, &str>, name: &str) -> String {
    fields.get(name).copied().unwrap_or_default().to_owned()
}

fn refresh_task_state(task: &mut Task, process_commands: Option<&HashMap<u32, String>>) {
    if !task.is_active() {
        return;
    }
    let process_missing = if task.pid == 0 {
        task.state == "running"
            || parse_time(&task.updated_at)
                .is_some_and(|time| (Utc::now() - time).num_seconds() >= 10)
    } else {
        !task_process_matches(task, process_commands)
    };
    if !process_missing {
        return;
    }

    task.state = "interrupted".to_owned();
    task.message = "process_missing".to_owned();
    if let Some(updated_at) = newest_artifact_time(task) {
        task.updated_at = updated_at.to_rfc3339();
    }
}

fn lane_process_commands() -> Option<HashMap<u32, String>> {
    let output = Command::new("ps")
        .args(["-axo", "pid=,command="])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&output.stdout);
    Some(
        text.lines()
            .filter_map(|line| {
                let line = line.trim_start();
                let separator = line.find(char::is_whitespace)?;
                let pid = line[..separator].parse().ok()?;
                let command = line[separator..].trim_start().to_owned();
                Some((pid, command))
            })
            .collect(),
    )
}

fn task_process_matches(task: &Task, process_commands: Option<&HashMap<u32, String>>) -> bool {
    let Some(process_commands) = process_commands else {
        return true;
    };
    process_commands
        .get(&task.pid)
        .is_some_and(|command| command.contains("_run") && command.contains(&task.id))
}

fn newest_artifact_time(task: &Task) -> Option<DateTime<Utc>> {
    [
        task.state_dir.join("state"),
        task.log.clone(),
        task.result.clone(),
    ]
    .into_iter()
    .filter_map(|path| fs::metadata(path).ok()?.modified().ok())
    .max()
    .map(DateTime::<Utc>::from)
}

fn read_tail(path: &Path, limit: u64) -> io::Result<Vec<u8>> {
    let mut file = File::open(path)?;
    let length = file.metadata()?.len();
    let start = length.saturating_sub(limit);
    file.seek(SeekFrom::Start(start))?;
    let mut bytes = Vec::with_capacity((length - start) as usize);
    file.read_to_end(&mut bytes)?;
    if start > 0
        && let Some(index) = bytes.iter().position(|byte| *byte == b'\n')
    {
        bytes.drain(..=index);
    }
    Ok(bytes)
}

fn parse_time(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|value| value.with_timezone(&Utc))
}

fn format_duration(seconds: i64) -> String {
    if seconds < 60 {
        return format!("{seconds}s");
    }
    if seconds < 3600 {
        return format!("{:02}:{:02}", seconds / 60, seconds % 60);
    }
    if seconds < 86_400 {
        return format!("{}h {:02}m", seconds / 3600, (seconds % 3600) / 60);
    }
    format!("{}d {:02}h", seconds / 86_400, (seconds % 86_400) / 3600)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn parses_v2_state() {
        let temp = tempfile::tempdir().unwrap();
        let state_dir = temp.path().join("task-123");
        fs::create_dir(&state_dir).unwrap();
        fs::write(
            state_dir.join("state"),
            "version=2\ntask_id=task-123\ntitle=Review UI\nstate=running\nlane=grok\nmodel=grok-4.5 / high\nmode=write\npid=42\nstarted_at=2026-08-09T12:00:00Z\nupdated_at=2026-08-09T12:00:02Z\ncwd=/tmp/repo\nlog=/tmp/lane.log\nresult=/tmp/result.txt\ndone=/tmp/done\n",
        )
        .unwrap();

        let task = parse_task(&state_dir.join("state"), &state_dir).unwrap();
        assert_eq!(task.id, "task-123");
        assert_eq!(task.title, "Review UI");
        assert_eq!(task.model, "grok-4.5 / high");
        assert!(task.is_active());
    }

    #[test]
    fn reads_only_tail_of_large_log() {
        let temp = tempfile::NamedTempFile::new().unwrap();
        let mut file = temp.reopen().unwrap();
        for index in 0..1000 {
            writeln!(file, "line-{index:04}").unwrap();
        }
        let bytes = read_tail(temp.path(), 128).unwrap();
        let text = String::from_utf8(bytes).unwrap();
        assert!(!text.contains("line-0000"));
        assert!(text.contains("line-0999"));
        assert!(text.starts_with("line-"));
    }

    #[test]
    fn finds_unique_task_prefix() {
        let tasks = vec![
            Task {
                id: "abc123".to_owned(),
                ..Task::default()
            },
            Task {
                id: "def456".to_owned(),
                ..Task::default()
            },
        ];
        assert_eq!(find_task(&tasks, "abc").unwrap().id, "abc123");
        assert!(find_task(&tasks, "missing").is_err());
    }

    #[test]
    fn marks_a_missing_lane_process_as_interrupted() {
        let temp = tempfile::tempdir().unwrap();
        let state_dir = temp.path().join("task-stale");
        fs::create_dir(&state_dir).unwrap();
        fs::write(
            state_dir.join("state"),
            "version=1\nstate=running\nlane=grok\npid=4294967295\nstarted_at=2026-08-09T12:00:00Z\nupdated_at=2026-08-09T12:00:02Z\n",
        )
        .unwrap();

        let tasks = discover_tasks(temp.path()).unwrap();

        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].state, "interrupted");
        assert_eq!(tasks[0].message, "process_missing");
        assert!(!tasks[0].is_active());
    }

    #[test]
    fn rejects_an_unrelated_process_with_the_same_pid() {
        let task = Task {
            id: "task-123".to_owned(),
            pid: 42,
            ..Task::default()
        };
        let mut process_commands = HashMap::from([(42, "sleep 60".to_owned())]);

        assert!(!task_process_matches(&task, Some(&process_commands)));

        process_commands.insert(
            42,
            "/bin/sh lane-supervisor.sh _run --state-dir /tmp/task-123".to_owned(),
        );
        assert!(task_process_matches(&task, Some(&process_commands)));
    }
}
