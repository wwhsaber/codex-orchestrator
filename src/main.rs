mod app;
mod model;
mod ui;

use std::io::{self, IsTerminal};
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use crossterm::event::{self, Event, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;

use crate::app::App;
use crate::model::{discover_tasks, find_task, state_root, stop_task};

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    /// Directory containing supervisor task state directories.
    #[arg(long, global = true)]
    state_root: Option<PathBuf>,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Open the interactive task dashboard.
    Tui,
    /// Watch live output from every running agent in an auto-updating pane grid.
    #[command(visible_aliases = ["watch-all", "live"])]
    Agents,
    /// Open the TUI focused on one task.
    Watch { task_id: String },
    /// Print known tasks without entering the TUI.
    List {
        /// Include finished tasks.
        #[arg(long)]
        all: bool,
    },
    /// Print the saved result for one task.
    Result { task_id: String },
    /// Stop one running task.
    Stop {
        task_id: String,
        /// Confirm the stop without an interactive prompt.
        #[arg(long)]
        yes: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let root = cli.state_root.unwrap_or_else(state_root);

    match cli.command {
        None | Some(Command::Tui) => run_tui(App::new(root, None)),
        Some(Command::Agents) => run_tui(App::agents(root)),
        Some(Command::Watch { task_id }) => run_tui(App::new(root, Some(task_id))),
        Some(Command::List { all }) => print_tasks(&root, all),
        Some(Command::Result { task_id }) => print_result(&root, &task_id),
        Some(Command::Stop { task_id, yes }) => stop_from_cli(&root, &task_id, yes),
    }
}

fn run_tui(app: App) -> Result<()> {
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!("the TUI requires an interactive terminal");
    }

    enable_raw_mode().context("enable terminal raw mode")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).context("enter alternate terminal screen")?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).context("create terminal")?;

    let result = run_event_loop(&mut terminal, app);

    disable_raw_mode().context("disable terminal raw mode")?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)
        .context("leave alternate terminal screen")?;
    terminal.show_cursor().context("show terminal cursor")?;
    result
}

fn run_event_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    mut app: App,
) -> Result<()> {
    app.refresh()?;
    while !app.should_quit {
        terminal.draw(|frame| ui::draw(frame, &mut app))?;

        if event::poll(Duration::from_millis(200))?
            && let Event::Key(key) = event::read()?
            && key.kind == KeyEventKind::Press
        {
            app.handle_key(key)?;
        }
        app.refresh_if_due()?;
    }
    Ok(())
}

fn print_tasks(root: &Path, all: bool) -> Result<()> {
    let tasks = discover_tasks(root)?;
    println!(
        "{:<11} {:<12} {:<28} {:<10} TASK",
        "STATE", "LANE", "MODEL", "ELAPSED"
    );
    for task in tasks.into_iter().filter(|task| all || task.is_active()) {
        println!(
            "{:<11} {:<12} {:<28} {:<10} {}",
            task.state.to_uppercase(),
            task.lane,
            task.model_display(),
            task.elapsed_label(),
            task.display_title()
        );
        println!("  id={} cwd={}", task.id, task.cwd.display());
    }
    Ok(())
}

fn print_result(root: &Path, task_id: &str) -> Result<()> {
    let tasks = discover_tasks(root)?;
    let task = find_task(&tasks, task_id)?;
    let text = std::fs::read_to_string(&task.result)
        .with_context(|| format!("read result {}", task.result.display()))?;
    print!("{text}");
    Ok(())
}

fn stop_from_cli(root: &Path, task_id: &str, yes: bool) -> Result<()> {
    let tasks = discover_tasks(root)?;
    let task = find_task(&tasks, task_id)?;
    if !task.is_active() {
        bail!("task {} is already {}", task.id, task.state);
    }
    if !yes {
        bail!("refusing to stop without --yes");
    }
    let output = stop_task(task)?;
    print!("{output}");
    Ok(())
}
