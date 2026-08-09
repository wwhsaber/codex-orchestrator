use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Cell, Clear, Paragraph, Row, Table, Wrap};

use crate::app::{App, View};
use crate::model::Task;

const ACCENT: Color = Color::Cyan;
const MUTED: Color = Color::DarkGray;

pub fn draw(frame: &mut Frame<'_>, app: &mut App) {
    match app.view {
        View::Dashboard => draw_dashboard(frame, app),
        View::Log | View::Result => draw_detail(frame, app),
    }
    if app.stop_confirmation {
        draw_stop_confirmation(frame, app);
    }
}

fn draw_dashboard(frame: &mut Frame<'_>, app: &mut App) {
    if frame.area().height < 20 {
        let areas = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(6),
                Constraint::Length(2),
            ])
            .split(frame.area());
        draw_header(frame, areas[0], app);
        draw_task_table(frame, areas[1], app);
        draw_footer(frame, areas[2], app);
        return;
    }

    let areas = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Percentage(46),
            Constraint::Min(7),
            Constraint::Length(2),
        ])
        .split(frame.area());

    draw_header(frame, areas[0], app);
    draw_task_table(frame, areas[1], app);
    draw_preview(frame, areas[2], app);
    draw_footer(frame, areas[3], app);
}

fn draw_header(frame: &mut Frame<'_>, area: Rect, app: &App) {
    let spinner = ["|", "/", "-", "\\"][app.tick % 4];
    let mut title_spans = vec![
        Span::styled(
            " CODEX ORCHESTRATOR ",
            Style::default()
                .fg(Color::Black)
                .bg(ACCENT)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled(
            format!(" {spinner} {}/{} run", app.active_count(), app.tasks.len()),
            Style::default().fg(Color::Green),
        ),
    ];
    if area.width >= 72 {
        title_spans.push(Span::styled(
            format!("  filter:{}", app.filter.label()),
            Style::default().fg(Color::Yellow),
        ));
    }
    let title = Line::from(title_spans);
    let path_width = area.width.saturating_sub(14) as usize;
    let root = Line::from(vec![
        Span::styled(" State root  ", Style::default().fg(MUTED)),
        Span::styled(
            fit_text(&app.root.display().to_string(), path_width),
            Style::default().fg(Color::White),
        ),
    ]);
    frame.render_widget(Paragraph::new(vec![title, root]), area);
}

fn draw_task_table(frame: &mut Frame<'_>, area: Rect, app: &mut App) {
    let tasks = app.visible_tasks();
    let compact = area.width < 96;
    let rows: Vec<Row<'static>> = tasks
        .iter()
        .map(|task| {
            if compact {
                compact_task_row(task)
            } else {
                task_row(task)
            }
        })
        .collect();
    let (header, widths): (Row<'static>, Vec<Constraint>) = if compact {
        (
            Row::new(["STATE", "LANE", "TIME", "TASK"]),
            vec![
                Constraint::Length(10),
                Constraint::Length(10),
                Constraint::Length(8),
                Constraint::Min(12),
            ],
        )
    } else {
        (
            Row::new([
                "STATE",
                "LANE",
                "MODEL",
                "MODE",
                "ELAPSED",
                "TASK",
                "WORKSPACE",
            ]),
            vec![
                Constraint::Length(10),
                Constraint::Length(11),
                Constraint::Length(25),
                Constraint::Length(7),
                Constraint::Length(9),
                Constraint::Min(18),
                Constraint::Length(18),
            ],
        )
    };
    let table = Table::new(rows, widths)
        .header(
            header
                .style(Style::default().fg(MUTED).add_modifier(Modifier::BOLD))
                .bottom_margin(1),
        )
        .row_highlight_style(
            Style::default()
                .bg(Color::Rgb(35, 42, 52))
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol(" > ")
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Gray))
                .title(" Agents "),
        );
    frame.render_stateful_widget(table, area, &mut app.table_state);
}

fn compact_task_row(task: &Task) -> Row<'static> {
    Row::new(vec![
        Cell::from(task.state.to_uppercase()).style(status_style(&task.state)),
        Cell::from(task.lane.clone()).style(Style::default().fg(ACCENT)),
        Cell::from(task.elapsed_label()),
        Cell::from(task.display_title().to_owned()),
    ])
}

fn task_row(task: &Task) -> Row<'static> {
    let style = status_style(&task.state);
    Row::new(vec![
        Cell::from(task.state.to_uppercase()).style(style),
        Cell::from(task.lane.clone()).style(Style::default().fg(ACCENT)),
        Cell::from(task.model_display().to_owned()),
        Cell::from(
            if task.mode.is_empty() {
                "--"
            } else {
                &task.mode
            }
            .to_owned(),
        ),
        Cell::from(task.elapsed_label()),
        Cell::from(task.display_title().to_owned()),
        Cell::from(task.workspace_name()).style(Style::default().fg(MUTED)),
    ])
}

fn draw_preview(frame: &mut Frame<'_>, area: Rect, app: &App) {
    let selected = app.selected_task();
    let title = selected
        .map(|task| {
            format!(
                " Live output - {} - {} - pid:{} ",
                task.lane, task.id, task.pid
            )
        })
        .unwrap_or_else(|| " Live output ".to_owned());
    let height = area.height.saturating_sub(2) as usize;
    let start = app.lines.len().saturating_sub(height);
    let lines: Vec<Line<'_>> = app.lines[start..]
        .iter()
        .map(|line| Line::raw(line.as_str()))
        .collect();
    let paragraph = Paragraph::new(lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Gray))
                .title(title),
        )
        .wrap(Wrap { trim: false });
    frame.render_widget(paragraph, area);
}

fn draw_detail(frame: &mut Frame<'_>, app: &App) {
    let areas = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(2),
        ])
        .split(frame.area());
    draw_header(frame, areas[0], app);

    let selected = app.selected_task();
    let view_name = if app.view == View::Result {
        "Result"
    } else {
        "Live log"
    };
    let title = selected
        .map(|task| {
            let terminal = if task.exit_code.is_empty() {
                task.state.clone()
            } else {
                format!("{}:{}", task.state, task.exit_code)
            };
            format!(
                " {view_name} - {} - {} - {} - {} ",
                task.lane,
                task.model_display(),
                task.display_title(),
                terminal
            )
        })
        .unwrap_or_else(|| format!(" {view_name} "));
    let visible_height = areas[1].height.saturating_sub(2) as usize;
    let max_scroll = app.lines.len().saturating_sub(visible_height);
    let scroll = if app.follow {
        max_scroll
    } else {
        app.scroll.min(max_scroll)
    };
    let lines: Vec<Line<'_>> = app
        .lines
        .iter()
        .map(|line| Line::raw(line.as_str()))
        .collect();
    let paragraph = Paragraph::new(lines)
        .scroll((scroll.min(u16::MAX as usize) as u16, 0))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(ACCENT))
                .title(title),
        )
        .wrap(Wrap { trim: false });
    frame.render_widget(paragraph, areas[1]);

    let mode = if app.follow { "FOLLOW" } else { "PAUSED" };
    let mut footer_spans = if areas[2].width < 80 {
        vec![
            key("Esc", "back"),
            key("Space", "follow"),
            key("Up/Down", "scroll"),
            key("q", "quit"),
        ]
    } else {
        vec![
            key("Esc", "dashboard"),
            key("Space", "follow"),
            key("Up/Down", "scroll"),
            key("l", "log"),
            key("r", "result"),
            key("s", "stop"),
            key("q", "quit"),
        ]
    };
    footer_spans.push(Span::styled(
        format!("  {mode}"),
        Style::default().fg(Color::Yellow),
    ));
    if areas[2].width >= 100 {
        footer_spans.push(Span::styled(
            selected
                .filter(|task| !task.message.is_empty())
                .map(|task| format!("  {}", task.message))
                .unwrap_or_default(),
            Style::default().fg(MUTED),
        ));
    }
    let footer = Line::from(footer_spans);
    frame.render_widget(Paragraph::new(footer), areas[2]);
}

fn draw_footer(frame: &mut Frame<'_>, area: Rect, app: &App) {
    let mut spans = if area.width < 80 {
        vec![
            key("Enter", "watch"),
            key("f", "filter"),
            key("s", "stop"),
            key("q", "quit"),
        ]
    } else {
        vec![
            key("Up/Down", "select"),
            key("Enter", "watch"),
            key("r", "result"),
            key("f/Tab", "filter"),
            key("s", "stop"),
            key("q", "quit"),
        ]
    };
    if let Some(notice) = &app.notice {
        spans.push(Span::styled(
            format!("  {notice}"),
            Style::default().fg(Color::Yellow),
        ));
    }
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

fn draw_stop_confirmation(frame: &mut Frame<'_>, app: &App) {
    let area = centered_rect(58, 7, frame.area());
    frame.render_widget(Clear, area);
    let task = app.selected_task();
    let prompt = task
        .map(|task| format!("Stop {} ({})?", task.display_title(), task.id))
        .unwrap_or_else(|| "Stop selected task?".to_owned());
    let paragraph = Paragraph::new(vec![
        Line::from(Span::styled(
            prompt,
            Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
        )),
        Line::raw(""),
        Line::from(vec![key("y", "confirm"), key("n/Esc", "cancel")]),
    ])
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Red))
            .title(" Confirm stop "),
    );
    frame.render_widget(paragraph, area);
}

fn centered_rect(width: u16, height: u16, area: Rect) -> Rect {
    let width = width.min(area.width.saturating_sub(2));
    let height = height.min(area.height.saturating_sub(2));
    Rect {
        x: area.x + area.width.saturating_sub(width) / 2,
        y: area.y + area.height.saturating_sub(height) / 2,
        width,
        height,
    }
}

fn key<'a>(name: &'a str, action: &'a str) -> Span<'a> {
    Span::styled(
        format!(" {name}:{action} "),
        Style::default().fg(Color::White).bg(Color::Rgb(45, 50, 60)),
    )
}

fn status_style(state: &str) -> Style {
    let color = match state {
        "running" => Color::Green,
        "starting" => Color::Yellow,
        "exited" => Color::Cyan,
        "failed" => Color::Red,
        "cancelled" => Color::Magenta,
        _ => Color::Gray,
    };
    Style::default().fg(color).add_modifier(Modifier::BOLD)
}

fn fit_text(value: &str, width: usize) -> String {
    let count = value.chars().count();
    if count <= width {
        return value.to_owned();
    }
    if width <= 3 {
        return ".".repeat(width);
    }
    let keep = width - 3;
    let head = keep / 2;
    let tail = keep - head;
    let start: String = value.chars().take(head).collect();
    let end: String = value
        .chars()
        .rev()
        .take(tail)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    format!("{start}...{end}")
}
