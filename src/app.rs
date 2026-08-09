use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::Result;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::widgets::TableState;

use crate::model::{Task, discover_tasks, read_task_content, stop_task};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Filter {
    All,
    Running,
    Finished,
}

impl Filter {
    pub fn next(self) -> Self {
        match self {
            Self::All => Self::Running,
            Self::Running => Self::Finished,
            Self::Finished => Self::All,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::All => "ALL",
            Self::Running => "RUNNING",
            Self::Finished => "FINISHED",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum View {
    Dashboard,
    Log,
    Result,
}

pub struct App {
    pub root: PathBuf,
    pub tasks: Vec<Task>,
    pub table_state: TableState,
    pub filter: Filter,
    pub view: View,
    pub follow: bool,
    pub scroll: usize,
    pub lines: Vec<String>,
    pub should_quit: bool,
    pub stop_confirmation: bool,
    pub notice: Option<String>,
    pub tick: usize,
    last_refresh: Instant,
    focused_task: Option<String>,
}

impl App {
    pub fn new(root: PathBuf, focused_task: Option<String>) -> Self {
        Self {
            root,
            tasks: Vec::new(),
            table_state: TableState::default().with_selected(Some(0)),
            filter: Filter::All,
            view: if focused_task.is_some() {
                View::Log
            } else {
                View::Dashboard
            },
            follow: true,
            scroll: 0,
            lines: Vec::new(),
            should_quit: false,
            stop_confirmation: false,
            notice: None,
            tick: 0,
            last_refresh: Instant::now() - Duration::from_secs(1),
            focused_task,
        }
    }

    pub fn refresh_if_due(&mut self) -> Result<()> {
        if self.last_refresh.elapsed() >= Duration::from_millis(500) {
            self.refresh()?;
        }
        Ok(())
    }

    pub fn refresh(&mut self) -> Result<()> {
        let previous_id = self.selected_task().map(|task| task.id.clone());
        self.tasks = discover_tasks(&self.root)?;
        let visible = self.visible_tasks();

        let wanted = self.focused_task.take().or(previous_id);
        let selected = wanted
            .as_ref()
            .and_then(|id| visible.iter().position(|task| &task.id == id))
            .unwrap_or_else(|| self.table_state.selected().unwrap_or_default())
            .min(visible.len().saturating_sub(1));
        self.table_state
            .select((!visible.is_empty()).then_some(selected));
        self.refresh_content()?;
        self.tick = self.tick.wrapping_add(1);
        self.last_refresh = Instant::now();
        Ok(())
    }

    pub fn visible_tasks(&self) -> Vec<Task> {
        self.tasks
            .iter()
            .filter(|task| match self.filter {
                Filter::All => true,
                Filter::Running => task.is_active(),
                Filter::Finished => !task.is_active(),
            })
            .cloned()
            .collect()
    }

    pub fn selected_task(&self) -> Option<&Task> {
        let selected = self.table_state.selected()?;
        self.tasks
            .iter()
            .filter(|task| match self.filter {
                Filter::All => true,
                Filter::Running => task.is_active(),
                Filter::Finished => !task.is_active(),
            })
            .nth(selected)
    }

    pub fn active_count(&self) -> usize {
        self.tasks.iter().filter(|task| task.is_active()).count()
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> Result<()> {
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            self.should_quit = true;
            return Ok(());
        }

        if self.stop_confirmation {
            match key.code {
                KeyCode::Char('y') | KeyCode::Char('Y') => self.confirm_stop()?,
                KeyCode::Esc | KeyCode::Char('n') | KeyCode::Char('N') => {
                    self.stop_confirmation = false;
                    self.notice = Some("Stop cancelled".to_owned());
                }
                _ => {}
            }
            return Ok(());
        }

        match key.code {
            KeyCode::Char('q') => self.should_quit = true,
            KeyCode::Esc => self.view = View::Dashboard,
            KeyCode::Tab | KeyCode::Char('f') if self.view == View::Dashboard => {
                self.filter = self.filter.next();
                self.table_state.select(Some(0));
                self.refresh_content()?;
            }
            KeyCode::Enter | KeyCode::Char('l') => {
                self.view = View::Log;
                self.follow = true;
                self.refresh_content()?;
            }
            KeyCode::Char('r') => {
                self.view = View::Result;
                self.follow = true;
                self.refresh_content()?;
            }
            KeyCode::Char('s') => {
                if self.selected_task().is_some_and(Task::is_active) {
                    self.stop_confirmation = true;
                } else {
                    self.notice = Some("Only a running task can be stopped".to_owned());
                }
            }
            KeyCode::Char(' ') if self.view != View::Dashboard => {
                self.follow = !self.follow;
            }
            KeyCode::Up | KeyCode::Char('k') => self.move_up(),
            KeyCode::Down | KeyCode::Char('j') => self.move_down(),
            KeyCode::PageUp if self.view != View::Dashboard => {
                self.follow = false;
                self.scroll = self.scroll.saturating_sub(10);
            }
            KeyCode::PageDown if self.view != View::Dashboard => {
                self.scroll = self.scroll.saturating_add(10);
            }
            KeyCode::Home if self.view != View::Dashboard => {
                self.follow = false;
                self.scroll = 0;
            }
            KeyCode::End if self.view != View::Dashboard => self.follow = true,
            _ => {}
        }
        Ok(())
    }

    fn move_up(&mut self) {
        if self.view == View::Dashboard {
            let selected = self.table_state.selected().unwrap_or_default();
            self.table_state.select(Some(selected.saturating_sub(1)));
            let _ = self.refresh_content();
        } else {
            self.follow = false;
            self.scroll = self.scroll.saturating_sub(1);
        }
    }

    fn move_down(&mut self) {
        if self.view == View::Dashboard {
            let count = self.visible_tasks().len();
            let selected = self.table_state.selected().unwrap_or_default();
            self.table_state
                .select((count > 0).then_some((selected + 1).min(count - 1)));
            let _ = self.refresh_content();
        } else {
            self.follow = false;
            self.scroll = self.scroll.saturating_add(1);
        }
    }

    fn refresh_content(&mut self) -> Result<()> {
        let result = self.view == View::Result;
        self.lines = match self.selected_task() {
            Some(task) => read_task_content(task, result)?,
            None => vec![format!("No tasks found in {}", self.root.display())],
        };
        if self.follow {
            self.scroll = self.lines.len().saturating_sub(1);
        }
        Ok(())
    }

    fn confirm_stop(&mut self) -> Result<()> {
        let Some(task) = self.selected_task().cloned() else {
            self.stop_confirmation = false;
            return Ok(());
        };
        let output = stop_task(&task)?;
        self.notice = Some(output.trim().to_owned());
        self.stop_confirmation = false;
        self.refresh()?;
        Ok(())
    }
}
