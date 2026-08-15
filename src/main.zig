const std = @import("std");
const r4os = @import("r4os");
const r4std = @import("r4std");

const AppApi = struct {
    sys: r4os.r4sys.Context,
    desk: r4os.r4desk.Context,
    draw: r4os.r4draw.Context,

    fn init(r4_app: *r4os.App) ?AppApi {
        return .{
            .sys = r4_app.system(),
            .desk = r4_app.desktop() orelse return null,
            .draw = r4_app.drawing() orelse return null,
        };
    }
};

const editor_capacity: usize = 64 * 1024;
const path_capacity: usize = 192;
const status_capacity: usize = 128;
const dir_buffer_capacity: usize = 4096;
const max_dir_items: usize = 96;
const dir_item_capacity: usize = 96;
const max_open_files: usize = 4;
const output_line_count: usize = 6;
const output_line_capacity: usize = 128;
const max_project_sources: usize = 6;
const max_project_imports: usize = 6;
const project_field_capacity: usize = 96;
const scratch_capacity: usize = 512;
const template_buffer_capacity: usize = 4096;
const manifest_arena_capacity: usize = 16 * 1024;
const project_name_capacity: usize = 32;
const build_arg_capacity: usize = 256;
const build_log_capacity: usize = 4096;
const version_text = "R4CODE 0.58.33";
const sdk_templates_root = "C:\\R4OS\\SDK\\Templates\\R4OS";
const default_projects_dir = "C:\\PROJECTS";
const default_projects_root = "C:\\PROJECTS\\";
const r4build_path = "C:\\SOFTWARE\\R4CODE\\R4BUILD.R4X";
const r4build_log_path = "C:\\SOFTWARE\\R4CODE\\LOGS\\R4BUILD.LOG";
const toolbar_h: i32 = 34;
const status_h: i32 = 20;
const output_h_min: i32 = 86;
const project_w_min: i32 = 176;
const project_w_max: i32 = 230;
const project_w_collapsed: i32 = 30;
const gap: i32 = 6;
const modifier_shift: u32 = 2;
const ctrl_n: u8 = 0x0E;
const ctrl_o: u8 = 0x0F;
const ctrl_s: u8 = 0x13;

const palette = r4os.gui.default_palette;
const accent: u32 = 0x0A246A;
const accent_text: u32 = 0xFFFFFF;
const panel_bg: u32 = 0xFFFFFF;
const gutter_bg: u32 = 0xE7E7E7;
const output_bg: u32 = 0x101010;
const output_fg: u32 = 0xD6FFD6;
const muted: u32 = 0x606060;

const Editor = r4os.gui.TextArea(editor_capacity);
const ProjectNameField = r4os.gui.TextField(project_name_capacity);

const TemplateRenderResult = struct {
    bytes: []const u8,
    ok: bool,
};

const Command = enum(u32) {
    file_new = 101,
    file_open = 102,
    file_open_folder = 103,
    file_save = 104,
    file_save_as = 105,
    file_exit = 106,
    file_new_c_console_project = 107,
    file_new_c_desktop_ok_project = 108,
    edit_cut = 201,
    edit_copy = 202,
    edit_paste = 203,
    view_project_panel = 301,
    build_build = 401,
    build_run = 402,
};

const ToolbarAction = enum(u8) {
    new_file,
    open_file,
    save_file,
    project_panel,
    build,
    run,
};

const AppMenus = struct {
    file_items: [8]r4os.gui.MenuItem = undefined,
    edit_items: [3]r4os.gui.MenuItem = undefined,
    view_items: [1]r4os.gui.MenuItem = undefined,
    build_items: [2]r4os.gui.MenuItem = undefined,
    menus: [4]r4os.gui.MenubarMenu = undefined,
};

const DialogMode = enum {
    none,
    open_file,
    save_as,
    open_folder,
    project_name,
    project_folder,
    save_prompt,
};

const PendingAction = enum {
    none,
    new_file,
    new_c_console_project,
    new_c_desktop_ok_project,
    open_file_dialog,
    open_folder_dialog,
    exit_app,
};

const ProjectTemplate = enum {
    none,
    c_console,
    c_desktop_ok,

    fn title(self: ProjectTemplate) []const u8 {
        return switch (self) {
            .none => "",
            .c_console => "R4X C Terminal Hello",
            .c_desktop_ok => "R4X C Desktop OK",
        };
    }

    fn folder(self: ProjectTemplate) []const u8 {
        return switch (self) {
            .none => "",
            .c_console => "R4X_C_Console",
            .c_desktop_ok => "R4X_C_Desktop_OK",
        };
    }

    fn defaultName(self: ProjectTemplate) []const u8 {
        return switch (self) {
            .none => "",
            .c_console => "HELLOC",
            .c_desktop_ok => "HELLOGUI",
        };
    }
};

const ProjectSummary = struct {
    loaded: bool = false,
    valid: bool = false,
    file: [path_capacity]u8 = .{0} ** path_capacity,
    name: [project_field_capacity]u8 = .{0} ** project_field_capacity,
    module_kind: [16]u8 = .{0} ** 16,
    language: [16]u8 = .{0} ** 16,
    build_profile: [project_field_capacity]u8 = .{0} ** project_field_capacity,
    app_class: [32]u8 = .{0} ** 32,
    artifact: [path_capacity]u8 = .{0} ** path_capacity,
    target_path: [path_capacity]u8 = .{0} ** path_capacity,
    state: [status_capacity]u8 = .{0} ** status_capacity,
    error_text: [status_capacity]u8 = .{0} ** status_capacity,
    sources: [max_project_sources][path_capacity]u8 = .{.{0} ** path_capacity} ** max_project_sources,
    source_count: usize = 0,
    imports: [max_project_imports][project_field_capacity]u8 = .{.{0} ** project_field_capacity} ** max_project_imports,
    import_count: usize = 0,

    fn clear(self: *ProjectSummary) void {
        self.* = .{};
    }

    fn setInvalid(self: *ProjectSummary, file_path: []const u8, message: []const u8) void {
        self.clear();
        self.loaded = true;
        self.valid = false;
        setZ(self.file[0..], file_path);
        setZ(self.error_text[0..], message);
    }

    fn load(self: *ProjectSummary, file_path: []const u8, project: r4os.r4mf.Manifest) void {
        self.clear();
        self.loaded = true;
        self.valid = true;
        setZ(self.file[0..], file_path);
        setZ(self.name[0..], project.name);
        setZ(self.module_kind[0..], project.kind.text());
        setZ(self.language[0..], project.language.?.text());
        setZ(self.build_profile[0..], r4os.r4mf.buildProfileName(project.language.?, project.entry_mode.?, project.app_class.?));
        setZ(self.app_class[0..], project.app_class.?.text());
        _ = buildArtifactPathFor(project.name, self.artifact[0..]);
        setZ(self.target_path[0..], project.target);
        setZ(self.state[0..], "Loaded");

        const sources = project.sources;
        self.source_count = @min(sources.len, max_project_sources);
        var i: usize = 0;
        while (i < self.source_count) : (i += 1) setZ(self.sources[i][0..], sources[i]);

        const imports = project.imports;
        self.import_count = @min(imports.len, max_project_imports);
        i = 0;
        while (i < self.import_count) : (i += 1) setZ(self.imports[i][0..], imports[i]);
    }

    fn markSourceDirty(self: *ProjectSummary) void {
        if (!self.loaded) return;
        self.valid = false;
        setZ(self.state[0..], "Modified");
        setZ(self.error_text[0..], "Project file modified; save to re-parse");
    }

    fn setState(self: *ProjectSummary, text: []const u8) void {
        if (!self.loaded) return;
        setZ(self.state[0..], text);
    }
};

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var sys = r4_app.system();
    if (hasSelftestSwitch(trim(zSlice(sys.argsRaw())))) {
        var selftest = R4CodeSelfTest{ .sys = sys };
        return selftest.run();
    }

    var ctx = AppApi.init(r4_app) orelse return r4os.abi.err_no_group;
    var app = App{ .ctx = &ctx };
    app.init();
    return app.run();
}

const App = struct {
    ctx: *AppApi,
    editor: Editor = .{},
    menubar_state: r4os.gui.MenubarState = .{},
    menu_storage: AppMenus = .{},
    dialog: DialogMode = .none,
    pending_action: PendingAction = .none,
    pressed_toolbar: ?ToolbarAction = null,
    quit_requested: bool = false,
    dirty: bool = false,
    loaded_truncated: bool = false,
    text_selecting: bool = false,
    project_collapsed: bool = false,
    w: i32 = 820,
    h: i32 = 520,
    dialog_selected_index: usize = 0,
    dialog_first_index: usize = 0,
    dialog_hover_index: ?usize = null,
    dialog_pressed_action: r4os.gui.DialogAction = .none,
    current_dir: [path_capacity]u8 = .{0} ** path_capacity,
    project_root: [path_capacity]u8 = .{0} ** path_capacity,
    current_path: [path_capacity]u8 = .{0} ** path_capacity,
    selected_path: [path_capacity]u8 = .{0} ** path_capacity,
    save_file_name: [path_capacity]u8 = .{0} ** path_capacity,
    project_name: ProjectNameField = .{},
    pending_template: ProjectTemplate = .none,
    status: [status_capacity]u8 = .{0} ** status_capacity,
    dirbuf: [dir_buffer_capacity]u8 = .{0} ** dir_buffer_capacity,
    dir_items: [max_dir_items][dir_item_capacity]u8 = .{.{0} ** dir_item_capacity} ** max_dir_items,
    dir_item_slices: [max_dir_items][]const u8 = [_][]const u8{""} ** max_dir_items,
    dir_item_count: usize = 0,
    open_paths: [max_open_files][path_capacity]u8 = .{.{0} ** path_capacity} ** max_open_files,
    open_count: usize = 0,
    active_open_index: usize = 0,
    output_lines: [output_line_count][output_line_capacity]u8 = .{.{0} ** output_line_capacity} ** output_line_count,
    output_count: usize = 0,
    project: ProjectSummary = .{},

    fn init(self: *App) void {
        setZ(self.current_dir[0..], "C:\\");
        setZ(self.project_root[0..], "C:\\");
        setZ(self.status[0..], "Ready");
        self.editor.focused = true;
        self.addOutput(version_text);
        self.addOutput("R4BUILD builds projects");
        self.openInitialArg();
    }

    fn run(self: *App) i32 {
        if (self.ctx.desk.programWindowId() >= 0) return self.runHosted();
        self.ctx.sys.println("R4CODE is a desktop GUI application.");
        self.ctx.sys.println("Start it from R4DESK or through GUI launch.");
        return 0;
    }

    fn runHosted(self: *App) i32 {
        _ = self.ctx.desk.guiSetTitle("R4Code");
        _ = self.ctx.desk.guiSetMinSize(720, 420);
        self.updateMetrics();
        self.render();

        while (!self.quit_requested) {
            var needs_render = false;
            if (self.ctx.sys.programShouldClose() and self.dialog == .none) {
                self.requestAction(.exit_app);
                needs_render = true;
            }

            var event: r4os.abi.GuiEvent = .{};
            while (self.ctx.desk.guiPollEvent(&event) > 0) {
                self.handleEvent(event);
                needs_render = true;
                if (self.quit_requested) break;
            }
            if (self.quit_requested) break;
            if (needs_render) self.render();
            self.ctx.sys.sleepTicks(3);
        }
        return 0;
    }

    fn handleEvent(self: *App, event: r4os.abi.GuiEvent) void {
        const kind: r4os.abi.GuiEventKind = @enumFromInt(event.kind);
        switch (kind) {
            .close => self.requestAction(.exit_app),
            .resize => {
                self.updateMetrics();
                self.editor.ensureCursorVisible(self.editorView());
            },
            .key_down => self.handleKey(r4os.gui.eventKey(event), event.modifiers),
            .mouse_down => self.handleMouseDown(event.x, event.y),
            .mouse_up => self.handleMouseUp(event.x, event.y),
            .mouse_move => self.handleMouseMove(event.x, event.y, event.buttons),
            else => {},
        }
    }

    fn updateMetrics(self: *App) void {
        var info: r4os.abi.GuiWindowInfo = .{};
        _ = self.ctx.desk.guiWindowInfo(&info);
        const canvas = r4os.gui.Canvas.init(&self.ctx.draw, info);
        self.w = clampI32(canvas.w, 720, 1400);
        self.h = clampI32(canvas.h, 420, 900);
    }

    fn handleKey(self: *App, raw_key: u8, modifiers: u32) void {
        var key = raw_key;
        if (key == 0x85 or key == 0x86) key = r4os.gui.Key.menu_focus;

        if (self.dialog != .none) {
            self.handleDialogKey(key);
            return;
        }

        if (self.menubar_state.isOpen() or key == r4os.gui.Key.menu_focus or key == r4os.gui.Key.f10) {
            var menu_storage: AppMenus = undefined;
            const menus = buildAppMenus(&menu_storage, self.project_collapsed);
            const result = self.menubar_state.keyAction(menus, key);
            if (result.hasCommand()) self.executeCommand(result.command_id);
            return;
        }

        if (self.handleShortcut(key)) return;

        const view = self.editorView();
        const changed = switch (key) {
            r4os.gui.Key.ctrl_c => blk: {
                if (self.editor.copyToClipboard(&self.ctx.desk)) {
                    self.setStatus("Copied selection");
                    break :blk true;
                }
                self.setStatus("No selection");
                break :blk false;
            },
            r4os.gui.Key.ctrl_x => blk: {
                if (self.editor.cutToClipboard(&self.ctx.desk)) {
                    self.markDirty("Cut selection");
                    break :blk true;
                }
                self.setStatus("No selection");
                break :blk false;
            },
            r4os.gui.Key.ctrl_v => blk: {
                if (self.editor.pasteFromClipboard(&self.ctx.desk, view)) {
                    self.markDirty("Pasted");
                    break :blk true;
                }
                self.setStatus("Clipboard empty or text full");
                break :blk false;
            },
            else => blk: {
                const did_change = self.editor.handleKeyEx(key, (modifiers & modifier_shift) != 0, view);
                if (did_change and isTextEditingKey(key)) self.markDirty("Modified");
                break :blk did_change;
            },
        };
        if (changed) self.editor.ensureCursorVisible(view);
    }

    fn handleShortcut(self: *App, key: u8) bool {
        switch (key) {
            ctrl_n => self.requestAction(.new_file),
            ctrl_o => self.requestAction(.open_file_dialog),
            ctrl_s => self.saveCurrentOrOpenSaveAs(),
            else => return false,
        }
        return true;
    }

    fn handleMouseDown(self: *App, x: i32, y: i32) void {
        if (self.dialog != .none) {
            self.handleDialogMouseDown(x, y);
            return;
        }

        var menu_storage: AppMenus = undefined;
        const menus = buildAppMenus(&menu_storage, self.project_collapsed);
        const menu_result = self.menubar_state.mouseDown(self.menubarRect(self.appCanvas()), menus, x, y);
        if (menu_result.action != .none or self.menubarRect(self.appCanvas()).contains(x, y)) return;

        if (self.toolbarActionAt(x, y)) |action| {
            self.pressed_toolbar = action;
            return;
        }

        if (self.projectToggleRect(self.appCanvas()).contains(x, y)) {
            self.pressed_toolbar = .project_panel;
            return;
        }

        if (self.editorIndexAt(self.appCanvas(), x, y)) |index| {
            self.beginEditorSelectionAt(index);
        }
    }

    fn handleMouseUp(self: *App, x: i32, y: i32) void {
        if (self.dialog != .none) {
            self.handleDialogMouseUp(x, y);
            return;
        }
        if (self.menubar_state.isOpen()) {
            var menu_storage: AppMenus = undefined;
            const menus = buildAppMenus(&menu_storage, self.project_collapsed);
            const result = self.menubar_state.mouseUp(self.menubarRect(self.appCanvas()), menus, x, y);
            if (result.hasCommand()) self.executeCommand(result.command_id);
            return;
        }

        if (self.pressed_toolbar) |pressed| {
            self.pressed_toolbar = null;
            if (pressed == .project_panel and self.projectToggleRect(self.appCanvas()).contains(x, y)) {
                self.toggleProjectPanel();
                return;
            }
            if (self.toolbarActionAt(x, y)) |released| {
                if (released == pressed) self.executeToolbar(released);
                return;
            }
        }

        if (self.text_selecting) {
            self.text_selecting = false;
            self.editor.finishMouseSelection();
        } else if (self.editorIndexAt(self.appCanvas(), x, y)) |index| {
            _ = self.editor.moveCursorTo(index, false, self.editorView());
            self.editor.focused = true;
        }
    }

    fn handleMouseMove(self: *App, x: i32, y: i32, buttons: u32) void {
        if (self.dialog != .none) return;
        if (self.menubar_state.isOpen()) {
            var menu_storage: AppMenus = undefined;
            const menus = buildAppMenus(&menu_storage, self.project_collapsed);
            _ = self.menubar_state.mouseMove(self.menubarRect(self.appCanvas()), menus, x, y);
            return;
        }
        if (self.text_selecting or (buttons & 1) != 0) {
            const index = self.editorIndexAt(self.appCanvas(), x, y) orelse return;
            if (!self.text_selecting) self.beginEditorSelectionAt(index);
            self.editor.dragMouseSelection(index, self.editorView());
        }
    }

    fn beginEditorSelectionAt(self: *App, index: usize) void {
        self.editor.focused = true;
        self.editor.beginMouseSelection(index, self.editorView());
        self.text_selecting = true;
    }

    fn editorIndexAt(self: *App, canvas: r4os.gui.Canvas, x: i32, y: i32) ?usize {
        const editor_rect = self.editorRect(canvas);
        if (!editor_rect.contains(x, y)) return null;
        const text_rect = r4os.gui.textAreaClientRect(editor_rect);
        return self.editor.hitTest(x - text_rect.x, y - text_rect.y, canvas.font.max_advance, canvas.font.line_height, self.editorView());
    }

    fn executeToolbar(self: *App, action: ToolbarAction) void {
        switch (action) {
            .new_file => self.requestAction(.new_file),
            .open_file => self.requestAction(.open_file_dialog),
            .save_file => self.saveCurrentOrOpenSaveAs(),
            .project_panel => self.toggleProjectPanel(),
            .build => _ = self.runBuild(),
            .run => self.runProjectArtifact(),
        }
    }

    fn executeCommand(self: *App, command_id: u32) void {
        self.menubar_state.close();
        switch (command_id) {
            @intFromEnum(Command.file_new) => self.requestAction(.new_file),
            @intFromEnum(Command.file_new_c_console_project) => self.requestAction(.new_c_console_project),
            @intFromEnum(Command.file_new_c_desktop_ok_project) => self.requestAction(.new_c_desktop_ok_project),
            @intFromEnum(Command.file_open) => self.requestAction(.open_file_dialog),
            @intFromEnum(Command.file_open_folder) => self.requestAction(.open_folder_dialog),
            @intFromEnum(Command.file_save) => self.saveCurrentOrOpenSaveAs(),
            @intFromEnum(Command.file_save_as) => self.openFileDialog(.save_as),
            @intFromEnum(Command.file_exit) => self.requestAction(.exit_app),
            @intFromEnum(Command.edit_cut) => {
                if (self.editor.cutToClipboard(&self.ctx.desk)) {
                    self.markDirty("Cut selection");
                } else {
                    self.setStatus("No selection");
                }
            },
            @intFromEnum(Command.edit_copy) => {
                if (self.editor.copyToClipboard(&self.ctx.desk)) {
                    self.setStatus("Copied selection");
                } else {
                    self.setStatus("No selection");
                }
            },
            @intFromEnum(Command.edit_paste) => {
                if (self.editor.pasteFromClipboard(&self.ctx.desk, self.editorView())) {
                    self.markDirty("Pasted");
                } else {
                    self.setStatus("Clipboard empty or text full");
                }
            },
            @intFromEnum(Command.view_project_panel) => self.toggleProjectPanel(),
            @intFromEnum(Command.build_build) => _ = self.runBuild(),
            @intFromEnum(Command.build_run) => self.runProjectArtifact(),
            else => {},
        }
    }

    fn requestAction(self: *App, action: PendingAction) void {
        if (self.dirty) {
            self.pending_action = action;
            self.dialog = .save_prompt;
            self.dialog_pressed_action = .none;
            self.setStatus("Unsaved changes");
            return;
        }
        self.performAction(action);
    }

    fn performAction(self: *App, action: PendingAction) void {
        switch (action) {
            .none => {},
            .new_file => self.newDocument(),
            .new_c_console_project => self.startProjectCreate(.c_console),
            .new_c_desktop_ok_project => self.startProjectCreate(.c_desktop_ok),
            .open_file_dialog => self.openFileDialog(.open_file),
            .open_folder_dialog => self.openFileDialog(.open_folder),
            .exit_app => self.quit_requested = true,
        }
    }

    fn newDocument(self: *App) void {
        self.editor.clear();
        self.editor.focused = true;
        zero(self.current_path[0..]);
        self.project.clear();
        self.dirty = false;
        self.loaded_truncated = false;
        self.pending_action = .none;
        self.dialog = .none;
        self.setStatus("New source file");
        self.addOutput("New file");
    }

    fn startProjectCreate(self: *App, template: ProjectTemplate) void {
        self.pending_template = template;
        self.project_name.set(template.defaultName());
        self.project_name.selectAll();
        self.project_name.focused = true;
        self.dialog = .project_name;
        self.dialog_pressed_action = .none;
        self.setStatus("Enter project name");
        self.addOutput(template.title());
    }

    fn confirmProjectName(self: *App) void {
        const name = self.project_name.value();
        if (!validProjectName(name)) {
            self.setStatus("Use A-Z, 0-9 or _");
            return;
        }

        var projects_dir: [path_capacity]u8 = .{0} ** path_capacity;
        setZ(projects_dir[0..], default_projects_dir);
        _ = self.ctx.sys.dirCreate(zptr(projects_dir[0..]));
        setZ(self.current_dir[0..], default_projects_root);
        if (!self.loadDirectory()) {
            setZ(self.current_dir[0..], "C:\\");
            if (!self.loadDirectory()) {
                self.dialog = .none;
                self.pending_template = .none;
                self.setStatus("Directory read failed");
                return;
            }
        }

        self.project_name.focused = false;
        self.dialog = .project_folder;
        self.dialog_selected_index = 0;
        self.dialog_first_index = 0;
        self.dialog_hover_index = null;
        self.dialog_pressed_action = .none;
        self.setStatus("Choose parent folder");
    }

    fn createProjectFromDialog(self: *App) void {
        if (self.pending_template == .none) {
            self.closeDialog("No template selected");
            return;
        }
        if (!validProjectName(self.project_name.value())) {
            self.dialog = .project_name;
            self.project_name.focused = true;
            self.setStatus("Use A-Z, 0-9 or _");
            return;
        }

        var project_dir: [path_capacity]u8 = .{0} ** path_capacity;
        if (!buildPathText(spanZ(self.current_dir[0..]), self.project_name.value(), project_dir[0..])) {
            self.setStatus("Project path too long");
            return;
        }
        if (self.pathExists(spanZ(project_dir[0..]))) {
            self.setStatus("Project folder exists");
            self.addOutput("Project folder exists");
            return;
        }

        var project_file_name: [path_capacity]u8 = .{0} ** path_capacity;
        if (!makeProjectFileName(project_file_name[0..])) {
            self.setStatus("Project name too long");
            return;
        }
        var project_file_path: [path_capacity]u8 = .{0} ** path_capacity;
        if (!buildPathText(spanZ(project_dir[0..]), spanZ(project_file_name[0..]), project_file_path[0..])) {
            self.setStatus("Project file path too long");
            return;
        }
        var src_dir: [path_capacity]u8 = .{0} ** path_capacity;
        if (!buildPathText(spanZ(project_dir[0..]), "src", src_dir[0..])) {
            self.setStatus("Source path too long");
            return;
        }
        var main_path: [path_capacity]u8 = .{0} ** path_capacity;
        if (!buildPathText(spanZ(src_dir[0..]), "main.c", main_path[0..])) {
            self.setStatus("Source file path too long");
            return;
        }

        var project_template_path: [path_capacity]u8 = .{0} ** path_capacity;
        var main_template_path: [path_capacity]u8 = .{0} ** path_capacity;
        if (!self.templateFilePath(self.pending_template, "module.R4MF.template", project_template_path[0..]) or
            !self.templateSourceFilePath(self.pending_template, "main.c.template", main_template_path[0..]))
        {
            self.setStatus("Template path too long");
            return;
        }

        var project_template: [template_buffer_capacity]u8 = undefined;
        var main_template: [template_buffer_capacity]u8 = undefined;
        const project_template_text = self.readTemplate(spanZ(project_template_path[0..]), project_template[0..]) orelse {
            self.setStatus("Project template missing");
            self.addOutput("Project template missing");
            return;
        };
        const main_template_text = self.readTemplate(spanZ(main_template_path[0..]), main_template[0..]) orelse {
            self.setStatus("Source template missing");
            self.addOutput("Source template missing");
            return;
        };

        var project_text: [template_buffer_capacity]u8 = undefined;
        var main_text: [template_buffer_capacity]u8 = undefined;
        const project_result = renderProjectTemplateText(project_template_text, self.project_name.value(), project_text[0..]);
        const main_result = renderProjectTemplateText(main_template_text, self.project_name.value(), main_text[0..]);
        if (!project_result.ok or !main_result.ok) {
            self.setStatus("Rendered project too large");
            return;
        }
        var manifest_arena: [manifest_arena_capacity]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(manifest_arena[0..]);
        _ = r4os.r4mf.parse(fba.allocator(), spanZ(project_file_path[0..]), project_result.bytes) catch |err| {
            self.setStatus("Generated R4MF invalid");
            self.addOutput(@errorName(err));
            return;
        };

        if (!self.ensureNewDirectory(spanZ(project_dir[0..])) or !self.ensureDirectory(spanZ(src_dir[0..]))) {
            self.setStatus("Project directory failed");
            self.addOutput("Project directory failed");
            return;
        }
        if (!self.writeTextFile(spanZ(project_file_path[0..]), project_result.bytes)) {
            self.setStatus("Project write failed");
            self.addOutput("Project write failed");
            return;
        }
        if (!self.writeTextFile(spanZ(main_path[0..]), main_result.bytes)) {
            self.setStatus("Source write failed");
            self.addOutput("Source write failed");
            return;
        }

        self.pending_template = .none;
        self.project_name.focused = false;
        self.dialog = .none;
        self.pending_action = .none;
        if (self.loadFile(project_file_path[0..])) {
            self.setStatus("Project created");
            self.addOutput("Project created");
        }
    }

    fn templateFilePath(self: *App, template: ProjectTemplate, file_name: []const u8, out: []u8) bool {
        _ = self;
        return templateFilePathFor(template, file_name, out);
    }

    fn templateSourceFilePath(self: *App, template: ProjectTemplate, file_name: []const u8, out: []u8) bool {
        _ = self;
        return templateSourceFilePathFor(template, file_name, out);
    }

    fn readTemplate(self: *App, path: []const u8, out: []u8) ?[]const u8 {
        var path_z: [path_capacity]u8 = .{0} ** path_capacity;
        setZ(path_z[0..], path);
        const read = self.ctx.sys.fileRead(zptr(path_z[0..]), out);
        if (read <= 0) return null;
        const len: usize = @intCast(read);
        if (len >= out.len) return null;
        return out[0..len];
    }

    fn writeTextFile(self: *App, path: []const u8, data: []const u8) bool {
        var path_z: [path_capacity]u8 = .{0} ** path_capacity;
        setZ(path_z[0..], path);
        const written = self.ctx.sys.fileWrite(zptr(path_z[0..]), data);
        if (written < 0) return false;
        return @as(usize, @intCast(written)) == data.len;
    }

    fn pathExists(self: *App, path: []const u8) bool {
        var path_z: [path_capacity]u8 = .{0} ** path_capacity;
        setZ(path_z[0..], path);
        if (self.ctx.sys.fileInfo(zptr(path_z[0..]))) |info| return info.exists != 0;
        return false;
    }

    fn ensureNewDirectory(self: *App, path: []const u8) bool {
        if (self.pathExists(path)) return false;
        return self.ensureDirectory(path);
    }

    fn ensureDirectory(self: *App, path: []const u8) bool {
        var path_z: [path_capacity]u8 = .{0} ** path_capacity;
        setZ(path_z[0..], path);
        if (self.ctx.sys.fileInfo(zptr(path_z[0..]))) |info| return info.exists != 0 and info.is_dir != 0;
        if (self.ctx.sys.dirCreate(zptr(path_z[0..])) < 0) return false;
        if (self.ctx.sys.fileInfo(zptr(path_z[0..]))) |info| return info.exists != 0 and info.is_dir != 0;
        return true;
    }

    fn saveCurrentOrOpenSaveAs(self: *App) void {
        if (self.current_path[0] == 0) {
            self.openFileDialog(.save_as);
            return;
        }
        if (self.loaded_truncated) {
            self.setStatus("Loaded text is truncated; use Save As");
            return;
        }
        _ = self.saveToCurrentPath();
    }

    fn saveToCurrentPath(self: *App) bool {
        if (self.loaded_truncated) {
            self.setStatus("Loaded text is truncated; use Save As");
            return false;
        }
        const result = r4std.text_file.saveFromTextArea(&self.ctx.sys, zptr(self.current_path[0..]), &self.editor);
        if (!result.ok) {
            self.setStatus("Save failed");
            self.addOutput("Save failed");
            return false;
        }
        self.dirty = false;
        self.loaded_truncated = false;
        self.setStatus("Saved");
        self.addOutput("Saved file");
        self.noteRecentDocument();
        self.rememberOpenPath(spanZ(self.current_path[0..]));
        self.refreshProjectFromEditor(spanZ(self.current_path[0..]));
        return true;
    }

    fn runBuild(self: *App) bool {
        if (self.dirty) {
            if (self.current_path[0] == 0) {
                self.setStatus("Save file before build");
                self.addOutput("Save file before build");
                return false;
            }
            if (!self.saveToCurrentPath()) return false;
        }
        if (!self.project.loaded or !self.project.valid) {
            self.setStatus("Open a valid module.R4MF project");
            self.addOutput("No valid project");
            return false;
        }

        var args: [build_arg_capacity]u8 = .{0} ** build_arg_capacity;
        var len: usize = 0;
        if (!appendText(args[0..], &len, "BUILD ") or !appendText(args[0..], &len, spanZ(self.project.file[0..]))) {
            self.setStatus("Build args too long");
            self.addOutput("Build args too long");
            self.project.setState("Build args too long");
            return false;
        }

        self.addOutput("R4BUILD build");
        const rc = self.ctx.sys.programRun(r4build_path, zptr(args[0..]));
        self.addBuildLogToOutput();
        if (rc == 0) {
            var artifact_path: [path_capacity]u8 = .{0} ** path_capacity;
            if (self.projectArtifactPath(artifact_path[0..])) {
                self.addOutput(spanZ(artifact_path[0..]));
            }
            self.project.setState("Build OK");
            self.setStatus("Build OK");
            return true;
        } else if (rc == 2) {
            self.project.setState("Build blocked");
            self.setStatus("Build blocked");
        } else if (rc == 3) {
            self.project.setState("Capability unsupported");
            self.setStatus("Capability unsupported");
        } else {
            self.project.setState("Build failed");
            self.setStatus("Build failed");
        }
        return false;
    }

    fn runProjectArtifact(self: *App) void {
        if (self.dirty) {
            if (self.current_path[0] == 0) {
                self.setStatus("Save file before run");
                self.addOutput("Save file before run");
                return;
            }
            if (!self.saveToCurrentPath()) return;
        }
        if (!self.project.loaded or !self.project.valid) {
            self.setStatus("Open a valid module.R4MF project");
            self.addOutput("No valid project");
            return;
        }

        var artifact_path: [path_capacity]u8 = .{0} ** path_capacity;
        if (!self.projectArtifactPath(artifact_path[0..])) {
            self.project.setState("Run path too long");
            self.setStatus("Run path too long");
            self.addOutput("Run path too long");
            return;
        }
        if (!self.pathExists(spanZ(artifact_path[0..]))) {
            self.project.setState("Build required");
            self.setStatus("Build project first");
            self.addOutput("Artifact missing");
            return;
        }

        self.addOutput("Run artifact");
        self.addOutput(spanZ(artifact_path[0..]));
        const rc = self.ctx.sys.programRun(zptr(artifact_path[0..]), "");
        if (rc == 0) {
            self.project.setState("Run OK");
            self.setStatus("Run OK");
        } else {
            self.project.setState("Run failed");
            self.setStatus("Run failed");
            self.addOutput("Run failed");
        }
    }

    fn projectArtifactPath(self: *App, out: []u8) bool {
        if (!self.project.loaded or !self.project.valid) return false;
        var project_dir: [path_capacity]u8 = .{0} ** path_capacity;
        setDirFromSpecificPath(spanZ(self.project.file[0..]), project_dir[0..]);
        return buildPathText(spanZ(project_dir[0..]), spanZ(self.project.artifact[0..]), out);
    }

    fn addBuildLogToOutput(self: *App) void {
        var log_path_z: [path_capacity]u8 = .{0} ** path_capacity;
        setZ(log_path_z[0..], r4build_log_path);
        var log_data: [build_log_capacity]u8 = undefined;
        const read = self.ctx.sys.fileRead(zptr(log_path_z[0..]), log_data[0..]);
        if (read <= 0) {
            self.addOutput("R4BUILD log missing");
            return;
        }
        const len: usize = @intCast(read);
        var start: usize = 0;
        var i: usize = 0;
        while (i <= len) : (i += 1) {
            if (i == len or log_data[i] == '\n') {
                var end = i;
                while (end > start and (log_data[end - 1] == '\r' or log_data[end - 1] == '\n')) end -= 1;
                if (end > start) self.addOutput(log_data[start..end]);
                start = i + 1;
            }
        }
    }

    fn openFileDialog(self: *App, mode: DialogMode) void {
        if (mode == .save_as) {
            if (self.current_path[0] != 0) {
                setZ(self.save_file_name[0..], baseName(spanZ(self.current_path[0..])));
            } else if (self.save_file_name[0] == 0) {
                setZ(self.save_file_name[0..], "UNTITLED.C");
            }
        }

        if (!self.loadDirectory()) {
            self.dialog = .none;
            self.setStatus("Directory read failed");
            return;
        }
        self.dialog = mode;
        self.dialog_selected_index = 0;
        self.dialog_first_index = 0;
        self.dialog_hover_index = null;
        self.dialog_pressed_action = .none;
        self.setStatus(switch (mode) {
            .open_file => "Choose .c, .zig, .R4MF or .txt",
            .open_folder => "Choose project/source folder",
            .save_as => "Choose name and folder",
            .project_folder => "Choose parent folder",
            else => "Ready",
        });
    }

    fn loadDirectory(self: *App) bool {
        zero(self.dirbuf[0..]);
        self.dir_item_count = 0;
        const read = self.ctx.sys.dirList(zptr(self.current_dir[0..]), self.dirbuf[0 .. self.dirbuf.len - 1]);
        if (read < 0) return false;
        const len: usize = @intCast(read);
        if (len < self.dirbuf.len) self.dirbuf[len] = 0;
        self.parseDirectoryItems(self.dirbuf[0..@min(len, self.dirbuf.len - 1)]);
        return true;
    }

    fn parseDirectoryItems(self: *App, data: []const u8) void {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= data.len) : (i += 1) {
            if (i == data.len or data[i] == '\n') {
                var end = i;
                while (end > start and (data[end - 1] == '\r' or data[end - 1] == '\n')) end -= 1;
                if (end > start) self.addDirItem(data[start..end]);
                start = i + 1;
            }
        }
    }

    fn addDirItem(self: *App, text: []const u8) void {
        if (self.dir_item_count >= max_dir_items) return;
        const index = self.dir_item_count;
        zero(self.dir_items[index][0..]);
        const len = @min(text.len, dir_item_capacity - 1);
        if (len > 0) @memcpy(self.dir_items[index][0..len], text[0..len]);
        self.dir_items[index][len] = 0;
        self.dir_item_slices[index] = self.dir_items[index][0..len];
        self.dir_item_count += 1;
    }

    fn handleDialogKey(self: *App, key: u8) void {
        switch (self.dialog) {
            .save_prompt => self.handleSavePromptAction(self.savePromptKeyAction(key)),
            .project_name => self.handleProjectNameKey(key),
            .open_file, .save_as, .open_folder, .project_folder => self.handleFileDialogKey(key),
            .none => {},
        }
    }

    fn handleProjectNameKey(self: *App, key: u8) void {
        const dialog = self.projectNameDialog();
        const action = dialog.keyAction(key);
        if (action == .cancel) {
            self.closeDialog("Cancelled");
            return;
        }
        if (action == .ok) {
            self.confirmProjectName();
            return;
        }
        if (self.project_name.handleClipboardKey(&self.ctx.desk, key)) self.setStatus("Enter project name");
    }

    fn handleFileDialogKey(self: *App, key: u8) void {
        if (key == r4os.gui.Key.escape) {
            self.closeDialog("Cancelled");
            return;
        }
        if (self.dialog == .save_as and key == r4os.gui.Key.backspace) {
            backspaceZ(self.save_file_name[0..], 0);
            return;
        }
        if (self.dialog == .save_as and isFileNameChar(key)) {
            appendZChar(self.save_file_name[0..], key);
            return;
        }

        const dialog = self.fileDialog();
        switch (dialog.keyAction(key)) {
            .ok => self.fileDialogOk(),
            .cancel => self.closeDialog("Cancelled"),
            .previous, .next => |action| {
                self.dialog_selected_index = dialog.selectedIndexForAction(action);
                self.dialog_first_index = self.fileDialog().firstIndexForSelection();
            },
            else => {},
        }
    }

    fn handleDialogMouseDown(self: *App, x: i32, y: i32) void {
        switch (self.dialog) {
            .save_prompt => self.dialog_pressed_action = self.savePromptActionAt(x, y),
            .project_name => self.handleProjectNameMouseDown(x, y),
            .open_file, .save_as, .open_folder, .project_folder => self.handleFileDialogMouseDown(x, y),
            .none => {},
        }
    }

    fn handleDialogMouseUp(self: *App, x: i32, y: i32) void {
        switch (self.dialog) {
            .save_prompt => {
                const action = self.savePromptActionAt(x, y);
                const pressed = self.dialog_pressed_action;
                self.dialog_pressed_action = .none;
                if (action == pressed) self.handleSavePromptAction(action);
            },
            .project_name => self.handleProjectNameMouseUp(x, y),
            .open_file, .save_as, .open_folder, .project_folder => self.handleFileDialogMouseUp(x, y),
            .none => {},
        }
    }

    fn handleProjectNameMouseDown(self: *App, x: i32, y: i32) void {
        const action = self.projectNameDialog().actionAt(x, y);
        self.dialog_pressed_action = action;
        if (action == .select) {
            self.project_name.focused = true;
            self.dialog_pressed_action = .none;
        }
    }

    fn handleProjectNameMouseUp(self: *App, x: i32, y: i32) void {
        const action = self.projectNameDialog().actionAt(x, y);
        const pressed = self.dialog_pressed_action;
        self.dialog_pressed_action = .none;
        if (action != pressed) return;
        switch (action) {
            .ok => self.confirmProjectName(),
            .cancel => self.closeDialog("Cancelled"),
            .select => self.project_name.focused = true,
            else => {},
        }
    }

    fn handleFileDialogMouseDown(self: *App, x: i32, y: i32) void {
        const dialog = self.fileDialog();
        const action = dialog.actionAt(x, y);
        if (action == .select) {
            if (dialog.indexAt(x, y)) |index| {
                self.dialog_selected_index = index;
                self.dialog_first_index = self.fileDialog().firstIndexForSelection();
                self.selectDirEntry(index);
            }
            return;
        }
        self.dialog_pressed_action = action;
    }

    fn handleFileDialogMouseUp(self: *App, x: i32, y: i32) void {
        const dialog = self.fileDialog();
        const action = dialog.actionAt(x, y);
        const pressed = self.dialog_pressed_action;
        self.dialog_pressed_action = .none;
        if (action != pressed) return;
        switch (action) {
            .ok => self.fileDialogOk(),
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn selectDirEntry(self: *App, index: usize) void {
        const kind = self.resolveDirEntry(index);
        if (kind < 0) {
            self.setStatus("Selection failed");
            return;
        }
        if (kind > 0) {
            if (self.dialog == .open_folder) {
                copyZ(self.project_root[0..], self.selected_path[0..]);
                copyZ(self.current_dir[0..], self.selected_path[0..]);
                self.project.clear();
                self.dialog = .none;
                self.setStatus("Project folder selected");
                self.addOutput("Project folder selected");
                return;
            }
            copyZ(self.current_dir[0..], self.selected_path[0..]);
            if (self.loadDirectory()) {
                self.dialog_selected_index = 0;
                self.dialog_first_index = 0;
                self.setStatus("Opened folder");
            } else {
                self.setStatus("Directory read failed");
            }
            return;
        }
        if (self.dialog == .save_as) setZ(self.save_file_name[0..], baseName(spanZ(self.selected_path[0..])));
        self.setStatus("Selected file");
    }

    fn resolveDirEntry(self: *App, index: usize) i32 {
        if (index >= self.dir_item_count) return -1;
        zero(self.selected_path[0..]);
        const kind = self.ctx.sys.dirEntry(zptr(self.current_dir[0..]), @intCast(index), self.selected_path[0 .. self.selected_path.len - 1]);
        self.selected_path[self.selected_path.len - 1] = 0;
        return kind;
    }

    fn fileDialogOk(self: *App) void {
        switch (self.dialog) {
            .save_as => self.saveFromDialog(),
            .open_folder => self.openFolderFromDialog(),
            .project_folder => self.createProjectFromDialog(),
            else => self.openFromDialog(),
        }
    }

    fn openFromDialog(self: *App) void {
        const kind = self.resolveDirEntry(self.dialog_selected_index);
        if (kind < 0) {
            self.setStatus("Selection failed");
            return;
        }
        if (kind > 0) {
            self.selectDirEntry(self.dialog_selected_index);
            return;
        }
        if (!isSupportedSourceFile(spanZ(self.selected_path[0..]))) {
            self.setStatus("Supported: .c .zig .R4MF .R4CP .txt");
            return;
        }
        if (self.loadFile(self.selected_path[0..])) {
            self.dialog = .none;
            self.pending_action = .none;
        }
    }

    fn openFolderFromDialog(self: *App) void {
        const kind = self.resolveDirEntry(self.dialog_selected_index);
        if (kind > 0) {
            copyZ(self.project_root[0..], self.selected_path[0..]);
            copyZ(self.current_dir[0..], self.selected_path[0..]);
            self.dialog = .none;
            self.setStatus("Project folder selected");
            self.addOutput("Project folder selected");
            return;
        }
        if (kind == 0) {
            self.setDirFromPath(spanZ(self.selected_path[0..]));
            copyZ(self.project_root[0..], self.current_dir[0..]);
            self.project.clear();
            self.dialog = .none;
            self.setStatus("Source folder selected");
            self.addOutput("Source folder selected");
            return;
        }
        self.setStatus("Selection failed");
    }

    fn saveFromDialog(self: *App) void {
        if (spanZ(self.save_file_name[0..]).len == 0) {
            self.setStatus("Enter a file name");
            return;
        }
        if (!buildPath(self.current_dir[0..], self.save_file_name[0..], self.selected_path[0..])) {
            self.setStatus("Path too long");
            return;
        }
        const result = r4std.text_file.saveFromTextArea(&self.ctx.sys, zptr(self.selected_path[0..]), &self.editor);
        if (!result.ok) {
            self.setStatus("Save failed");
            self.addOutput("Save failed");
            return;
        }
        copyZ(self.current_path[0..], self.selected_path[0..]);
        self.setDirFromPath(spanZ(self.current_path[0..]));
        self.dirty = false;
        self.loaded_truncated = false;
        self.dialog = .none;
        self.setStatus("Saved");
        self.addOutput("Saved file");
        self.noteRecentDocument();
        self.rememberOpenPath(spanZ(self.current_path[0..]));
        self.refreshProjectFromEditor(spanZ(self.current_path[0..]));
        const action = self.pending_action;
        self.pending_action = .none;
        self.performAction(action);
    }

    fn loadFile(self: *App, path_buffer: []const u8) bool {
        var path_copy: [path_capacity]u8 = .{0} ** path_capacity;
        copyZ(path_copy[0..], path_buffer);
        const result = r4std.text_file.loadIntoTextArea(&self.ctx.sys, zptr(path_copy[0..]), &self.editor, self.editorView());
        if (!result.ok) {
            self.setStatus("Open failed");
            self.addOutput("Open failed");
            return false;
        }

        copyZ(self.current_path[0..], path_copy[0..]);
        self.setDirFromPath(spanZ(self.current_path[0..]));
        self.dirty = false;
        self.loaded_truncated = result.truncated;
        self.editor.focused = true;
        self.editor.ensureCursorVisible(self.editorView());
        self.setStatus(if (self.loaded_truncated) "Opened truncated at 64 KB limit" else "Opened file");
        self.addOutput("Opened file");
        self.noteRecentDocument();
        self.rememberOpenPath(spanZ(self.current_path[0..]));
        self.refreshProjectFromEditor(spanZ(self.current_path[0..]));
        return true;
    }

    fn refreshProjectFromEditor(self: *App, project_path: []const u8) void {
        if (isR4MFFile(project_path)) {
            self.loadProjectFromEditor(project_path);
        } else if (isR4CPFile(project_path)) {
            const message = "Historical R4CP: use R4BUILD CONVERT";
            self.project.setInvalid(project_path, message);
            self.setStatus(message);
            self.addOutput(message);
        }
    }

    fn loadProjectFromEditor(self: *App, project_path: []const u8) void {
        var manifest_arena: [manifest_arena_capacity]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(manifest_arena[0..]);
        const parsed = r4os.r4mf.parse(fba.allocator(), project_path, self.editor.value()) catch |err| {
            const message = @errorName(err);
            self.project.setInvalid(project_path, message);
            self.setStatus("Project parse failed");
            self.addOutput("Project parse failed");
            self.addOutput(message);
            return;
        };
        self.project.load(project_path, parsed);
        self.setDirFromPath(project_path);
        copyZ(self.project_root[0..], self.current_dir[0..]);
        self.setStatus("Project loaded");
        self.addOutput("Project loaded");
        self.addOutput(r4os.r4mf.buildProfileName(parsed.language.?, parsed.entry_mode.?, parsed.app_class.?));
    }

    fn closeDialog(self: *App, status_text: []const u8) void {
        const old_dialog = self.dialog;
        self.dialog = .none;
        self.pending_action = .none;
        self.dialog_pressed_action = .none;
        if (old_dialog == .project_name or old_dialog == .project_folder) {
            self.pending_template = .none;
            self.project_name.focused = false;
        }
        self.setStatus(status_text);
    }

    fn savePromptKeyAction(self: *App, key: u8) r4os.gui.DialogAction {
        if (key == 'd' or key == 'D' or key == 'n' or key == 'N') return .no;
        var button_storage: [3]r4os.gui.DialogButton = undefined;
        const buttons = self.savePromptButtons(&button_storage);
        return r4os.gui.dialogKeyAction(buttons, .ok, key);
    }

    fn handleSavePromptAction(self: *App, action: r4os.gui.DialogAction) void {
        switch (action) {
            .ok => {
                self.dialog = .none;
                if (self.current_path[0] == 0) {
                    self.openFileDialog(.save_as);
                    return;
                }
                if (self.saveToCurrentPath()) {
                    const pending = self.pending_action;
                    self.pending_action = .none;
                    self.performAction(pending);
                }
            },
            .no => {
                const pending = self.pending_action;
                self.pending_action = .none;
                self.dialog = .none;
                self.dirty = false;
                self.performAction(pending);
            },
            .cancel => self.closeDialog("Cancelled"),
            else => {},
        }
    }

    fn render(self: *App) void {
        var paint = switch (r4os.app_gui.beginPaintForSize(&self.ctx.draw, self.w, self.h)) {
            .paint => |value| value,
            .failure => return,
        };
        defer paint.discard();
        const canvas = paint.canvas;
        var scratch: [scratch_capacity]u8 = .{0} ** scratch_capacity;
        _ = canvas.clear(palette.face);
        self.drawToolbar(canvas, scratch[0..]);
        self.drawWorkspace(canvas, scratch[0..]);
        self.drawStatus(canvas, scratch[0..]);
        _ = canvas.menubar(self.menubar(), scratch[0..]);
        self.drawDialog(canvas, scratch[0..]);
        _ = paint.present();
    }

    fn drawToolbar(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const y = r4os.gui.default_metrics.menu_bar_h;
        _ = canvas.rect(.{ .x = 0, .y = y, .w = self.w, .h = toolbar_h }, palette.face);
        _ = canvas.rect(.{ .x = 0, .y = y + toolbar_h - 1, .w = self.w, .h = 1 }, palette.face_shadow);
        self.drawToolbarButton(canvas, scratch, .new_file, "New");
        self.drawToolbarButton(canvas, scratch, .open_file, "Open");
        self.drawToolbarButton(canvas, scratch, .save_file, "Save");
        self.drawToolbarButton(canvas, scratch, .project_panel, if (self.project_collapsed) "Project +" else "Project -");
        self.drawToolbarButton(canvas, scratch, .build, "Build");
        self.drawToolbarButton(canvas, scratch, .run, "Run");
        _ = canvas.label(.{
            .rect = .{ .x = 534, .y = y + 8, .w = @max(80, self.w - 542), .h = 18 },
            .text = "R4BUILD builds project artifacts",
            .fg = muted,
            .bg = palette.face,
        }, scratch);
    }

    fn drawToolbarButton(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, action: ToolbarAction, text: []const u8) void {
        _ = canvas.button(.{
            .rect = self.toolbarButtonRect(action),
            .text = text,
            .state = if (self.pressed_toolbar != null and self.pressed_toolbar.? == action) .pressed else .normal,
        }, scratch);
    }

    fn drawWorkspace(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const project_panel = self.projectRect(canvas);
        const editor = self.editorRect(canvas);
        const output = self.outputRect(canvas);
        self.drawProjectPanel(canvas, scratch, project_panel);
        _ = canvas.rect(editor, palette.client_bg);
        _ = self.editor.draw(canvas, editor, scratch);
        self.drawOutputPanel(canvas, scratch, output);
    }

    fn drawProjectPanel(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, rect: r4os.gui.Rect) void {
        drawFrame(canvas, rect, panel_bg);
        _ = canvas.rect(.{ .x = rect.x + 2, .y = rect.y + 2, .w = rect.w - 4, .h = 22 }, accent);
        const toggle_text = if (self.project_collapsed) ">>" else "<<";
        _ = canvas.button(.{
            .rect = self.projectToggleRect(canvas),
            .text = toggle_text,
            .state = if (self.pressed_toolbar != null and self.pressed_toolbar.? == .project_panel) .pressed else .normal,
        }, scratch);
        if (self.project_collapsed) return;

        _ = canvas.label(.{ .rect = .{ .x = rect.x + 8, .y = rect.y + 5, .w = rect.w - 42, .h = 16 }, .text = "Project", .fg = accent_text, .bg = accent }, scratch);
        if (self.project.loaded) {
            self.drawLoadedProject(canvas, scratch, rect);
            return;
        }

        _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = rect.y + 34, .w = rect.w - 20, .h = 16 }, .text = "Root:", .fg = muted, .bg = panel_bg }, scratch);
        _ = canvas.textClipped(rect.x + 10, rect.y + 52, rect.w - 20, scratch, spanZ(self.project_root[0..]), palette.text, panel_bg);
        _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = rect.y + 78, .w = rect.w - 20, .h = 16 }, .text = "Open files:", .fg = muted, .bg = panel_bg }, scratch);
        if (self.open_count == 0) {
            _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = rect.y + 98, .w = rect.w - 20, .h = 16 }, .text = "No file loaded", .fg = muted, .bg = panel_bg }, scratch);
        } else {
            var i: usize = 0;
            while (i < self.open_count and i < 4) : (i += 1) {
                const y = rect.y + 98 + @as(i32, @intCast(i)) * 18;
                const fg = if (i == self.active_open_index) accent else palette.text;
                _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, baseName(spanZ(self.open_paths[i][0..])), fg, panel_bg);
            }
        }
    }

    fn drawLoadedProject(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, rect: r4os.gui.Rect) void {
        var y = rect.y + 34;
        _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = y, .w = rect.w - 20, .h = 16 }, .text = "Name:", .fg = muted, .bg = panel_bg }, scratch);
        y += 18;
        _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, spanZ(self.project.name[0..]), palette.text, panel_bg);
        y += 20;
        if (!self.project.valid) {
            _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = y, .w = rect.w - 20, .h = 16 }, .text = "Invalid project:", .fg = 0xAA0000, .bg = panel_bg }, scratch);
            y += 18;
            _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, spanZ(self.project.error_text[0..]), 0xAA0000, panel_bg);
            return;
        }

        _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, spanZ(self.project.build_profile[0..]), accent, panel_bg);
        y += 18;
        _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, spanZ(self.project.artifact[0..]), palette.text, panel_bg);
        y += 20;
        _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, spanZ(self.project.state[0..]), muted, panel_bg);
        y += 22;
        _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = y, .w = rect.w - 20, .h = 16 }, .text = "Sources:", .fg = muted, .bg = panel_bg }, scratch);
        y += 18;
        var i: usize = 0;
        while (i < self.project.source_count and i < 3) : (i += 1) {
            _ = canvas.textClipped(rect.x + 14, y, rect.w - 24, scratch, spanZ(self.project.sources[i][0..]), palette.text, panel_bg);
            y += 17;
        }
        if (self.project.source_count > 3) {
            _ = canvas.label(.{ .rect = .{ .x = rect.x + 14, .y = y, .w = rect.w - 24, .h = 16 }, .text = "...", .fg = muted, .bg = panel_bg }, scratch);
            y += 17;
        }
        _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = y, .w = rect.w - 20, .h = 16 }, .text = "Imports:", .fg = muted, .bg = panel_bg }, scratch);
        y += 18;
        i = 0;
        while (i < self.project.import_count and i < 3) : (i += 1) {
            _ = canvas.textClipped(rect.x + 14, y, rect.w - 24, scratch, spanZ(self.project.imports[i][0..]), palette.text, panel_bg);
            y += 17;
        }
        y += 4;
        _ = canvas.label(.{ .rect = .{ .x = rect.x + 10, .y = y, .w = rect.w - 20, .h = 16 }, .text = "Target:", .fg = muted, .bg = panel_bg }, scratch);
        y += 18;
        _ = canvas.textClipped(rect.x + 10, y, rect.w - 20, scratch, spanZ(self.project.target_path[0..]), palette.text, panel_bg);
    }

    fn drawOutputPanel(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, rect: r4os.gui.Rect) void {
        drawFrame(canvas, rect, output_bg);
        _ = canvas.label(.{ .rect = .{ .x = rect.x + 8, .y = rect.y + 6, .w = rect.w - 16, .h = 16 }, .text = "Output", .fg = accent_text, .bg = output_bg }, scratch);
        var i: usize = 0;
        while (i < self.output_count and i < output_line_count) : (i += 1) {
            _ = canvas.textClipped(rect.x + 8, rect.y + 26 + @as(i32, @intCast(i)) * 16, rect.w - 16, scratch, spanZ(self.output_lines[i][0..]), output_fg, output_bg);
        }
    }

    fn drawStatus(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.statusRect(canvas);
        _ = canvas.rect(rect, palette.face);
        _ = canvas.rect(.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = 1 }, palette.face_shadow);
        const status_text = if (self.status[0] != 0) spanZ(self.status[0..]) else "Ready";
        _ = r4os.gui.drawTextInRect(canvas, rect.inset(6, 2), scratch, status_text, .left, palette.text, palette.face);
        var right_buf: [96]u8 = .{0} ** 96;
        self.formatRightStatus(right_buf[0..]);
        _ = r4os.gui.drawTextInRect(canvas, rect.inset(6, 2), scratch, spanZ(right_buf[0..]), .right, palette.text, palette.face);
    }

    fn drawDialog(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        switch (self.dialog) {
            .none => {},
            .open_file, .save_as, .open_folder, .project_folder => _ = canvas.fileDialog(self.fileDialog(), scratch),
            .project_name => self.drawProjectNameDialog(canvas, scratch),
            .save_prompt => self.drawSavePrompt(canvas, scratch),
        }
    }

    fn drawProjectNameDialog(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const dialog = self.projectNameDialog();
        _ = canvas.inputDialog(dialog, scratch);
        _ = self.project_name.draw(canvas, dialog.valueRect(), scratch);
    }

    fn drawSavePrompt(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.savePromptRect();
        var button_storage: [3]r4os.gui.DialogButton = undefined;
        _ = r4os.gui.drawDialogFrame(canvas, rect, scratch, "R4Code", palette);
        _ = r4os.gui.drawTextInRect(canvas, rect.inset(12, 34), scratch, "Save changes to this file?", .left, palette.text, palette.face);
        _ = r4os.gui.drawDialogButtons(canvas, rect, scratch, self.savePromptButtons(&button_storage), .ok, self.dialog_pressed_action, .right, palette);
    }

    fn appCanvas(self: *App) r4os.gui.Canvas {
        return r4os.gui.Canvas.initSize(&self.ctx.draw, self.w, self.h);
    }

    fn menubar(self: *App) r4os.gui.Menubar {
        const menus = buildAppMenus(&self.menu_storage, self.project_collapsed);
        return .{
            .rect = self.menubarRect(self.appCanvas()),
            .menus = menus,
            .state = self.menubar_state,
        };
    }

    fn menubarRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        _ = self;
        return .{ .x = 0, .y = 0, .w = canvas.w, .h = r4os.gui.default_metrics.menu_bar_h };
    }

    fn toolbarButtonRect(self: *App, action: ToolbarAction) r4os.gui.Rect {
        _ = self;
        const y = r4os.gui.default_metrics.menu_bar_h + 5;
        return switch (action) {
            .new_file => .{ .x = 8, .y = y, .w = 72, .h = 24 },
            .open_file => .{ .x = 86, .y = y, .w = 72, .h = 24 },
            .save_file => .{ .x = 164, .y = y, .w = 72, .h = 24 },
            .project_panel => .{ .x = 250, .y = y, .w = 96, .h = 24 },
            .build => .{ .x = 360, .y = y, .w = 72, .h = 24 },
            .run => .{ .x = 438, .y = y, .w = 72, .h = 24 },
        };
    }

    fn toolbarActionAt(self: *App, x: i32, y: i32) ?ToolbarAction {
        const actions = [_]ToolbarAction{ .new_file, .open_file, .save_file, .project_panel, .build, .run };
        for (actions) |action| {
            if (self.toolbarButtonRect(action).contains(x, y)) return action;
        }
        return null;
    }

    fn contentTop(self: *App) i32 {
        _ = self;
        return r4os.gui.default_metrics.menu_bar_h + toolbar_h + gap;
    }

    fn projectRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const output = self.outputRect(canvas);
        const width = if (self.project_collapsed) project_w_collapsed else clampI32(@divTrunc(canvas.w, 4), project_w_min, project_w_max);
        return .{ .x = gap, .y = self.contentTop(), .w = width, .h = @max(40, output.y - self.contentTop() - gap) };
    }

    fn projectToggleRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const rect = self.projectRect(canvas);
        return .{ .x = rect.x + rect.w - 28, .y = rect.y + 3, .w = 22, .h = 18 };
    }

    fn editorRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const project = self.projectRect(canvas);
        const output = self.outputRect(canvas);
        return .{
            .x = project.right() + gap,
            .y = self.contentTop(),
            .w = @max(80, canvas.w - project.right() - gap * 2),
            .h = @max(60, output.y - self.contentTop() - gap),
        };
    }

    fn outputRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        const status = self.statusRect(canvas);
        const available_h = @max(120, status.y - self.contentTop() - gap * 2);
        const output_h = clampI32(@divTrunc(available_h, 4), output_h_min, 150);
        return .{ .x = gap, .y = status.y - output_h - gap, .w = canvas.w - gap * 2, .h = output_h };
    }

    fn statusRect(self: *App, canvas: r4os.gui.Canvas) r4os.gui.Rect {
        _ = self;
        return .{ .x = 0, .y = @max(0, canvas.h - status_h), .w = canvas.w, .h = status_h };
    }

    fn editorView(self: *App) r4os.gui.TextAreaView {
        return r4os.gui.textAreaViewForRect(self.appCanvas(), self.editorRect(self.appCanvas()));
    }

    fn fileDialog(self: *App) r4os.gui.FileDialog {
        const mode: r4os.gui.FileDialogMode = if (self.dialog == .save_as) .save else .open;
        return .{
            .rect = self.fileDialogRect(),
            .title = switch (self.dialog) {
                .save_as => "Save As",
                .open_folder => "Open Folder",
                .project_folder => "Project Folder",
                else => "Open Source",
            },
            .path = spanZ(self.current_dir[0..]),
            .items = self.dir_item_slices[0..self.dir_item_count],
            .mode = mode,
            .file_name = if (mode == .save) spanZ(self.save_file_name[0..]) else "",
            .ok_text = switch (self.dialog) {
                .save_as => "Save",
                .open_folder => "Use",
                .project_folder => "Create",
                else => "Open",
            },
            .cancel_text = "Cancel",
            .selected_index = @min(self.dialog_selected_index, if (self.dir_item_count == 0) 0 else self.dir_item_count - 1),
            .hover_index = self.dialog_hover_index,
            .first_index = self.dialog_first_index,
            .focus_action = .select,
            .pressed_action = self.dialog_pressed_action,
        };
    }

    fn fileDialogRect(self: *App) r4os.gui.Rect {
        const canvas = self.appCanvas();
        const width = @min(540, @max(320, canvas.w - 24));
        const height = @min(350, @max(230, canvas.h - 36));
        return r4os.gui.centeredRect(canvas.bounds(), width, height);
    }

    fn savePromptRect(self: *App) r4os.gui.Rect {
        return r4os.gui.centeredRect(self.appCanvas().bounds(), @min(360, @max(260, self.w - 40)), 116);
    }

    fn projectNameDialogRect(self: *App) r4os.gui.Rect {
        return r4os.gui.centeredRect(self.appCanvas().bounds(), @min(360, @max(280, self.w - 40)), 116);
    }

    fn projectNameDialog(self: *App) r4os.gui.InputDialog {
        return .{
            .rect = self.projectNameDialogRect(),
            .title = self.pending_template.title(),
            .label = "Project name:",
            .value = self.project_name.value(),
            .ok_text = "Next",
            .cancel_text = "Cancel",
            .focus_action = .select,
            .pressed_action = self.dialog_pressed_action,
        };
    }

    fn savePromptButtons(self: *App, out: *[3]r4os.gui.DialogButton) []const r4os.gui.DialogButton {
        _ = self;
        out.* = .{
            .{ .action = .ok, .text = "Save", .role = .default },
            .{ .action = .no, .text = "Don't Save" },
            .{ .action = .cancel, .text = "Cancel", .role = .cancel },
        };
        return out[0..];
    }

    fn savePromptActionAt(self: *App, x: i32, y: i32) r4os.gui.DialogAction {
        var button_storage: [3]r4os.gui.DialogButton = undefined;
        return r4os.gui.dialogButtonActionAt(self.savePromptRect(), self.savePromptButtons(&button_storage), .right, x, y);
    }

    fn setDirFromPath(self: *App, path: []const u8) void {
        setDirFromSpecificPath(path, self.current_dir[0..]);
    }

    fn markDirty(self: *App, status_text: []const u8) void {
        self.dirty = true;
        self.loaded_truncated = false;
        if (isR4MFFile(spanZ(self.current_path[0..]))) self.project.markSourceDirty();
        self.setStatus(status_text);
    }

    fn toggleProjectPanel(self: *App) void {
        self.project_collapsed = !self.project_collapsed;
        self.setStatus(if (self.project_collapsed) "Project panel collapsed" else "Project panel expanded");
    }

    fn formatRightStatus(self: *App, out: []u8) void {
        zero(out);
        if (self.loaded_truncated) {
            setZ(out, "TRUNCATED");
            return;
        }
        if (self.dirty) {
            setZ(out, "Modified");
            return;
        }
        if (self.current_path[0] != 0) {
            setZ(out, baseName(spanZ(self.current_path[0..])));
            return;
        }
        setZ(out, "Untitled");
    }

    fn setStatus(self: *App, message: []const u8) void {
        setZ(self.status[0..], message);
    }

    fn addOutput(self: *App, message: []const u8) void {
        if (self.output_count < output_line_count) {
            setZ(self.output_lines[self.output_count][0..], message);
            self.output_count += 1;
            return;
        }
        var i: usize = 1;
        while (i < output_line_count) : (i += 1) {
            copyZ(self.output_lines[i - 1][0..], self.output_lines[i][0..]);
        }
        setZ(self.output_lines[output_line_count - 1][0..], message);
    }

    fn rememberOpenPath(self: *App, path: []const u8) void {
        if (path.len == 0) return;
        var i: usize = 0;
        while (i < self.open_count) : (i += 1) {
            if (equalsIgnoreCase(spanZ(self.open_paths[i][0..]), path)) {
                self.active_open_index = i;
                return;
            }
        }
        if (self.open_count < max_open_files) {
            setZ(self.open_paths[self.open_count][0..], path);
            self.active_open_index = self.open_count;
            self.open_count += 1;
            return;
        }
        i = 1;
        while (i < max_open_files) : (i += 1) copyZ(self.open_paths[i - 1][0..], self.open_paths[i][0..]);
        setZ(self.open_paths[max_open_files - 1][0..], path);
        self.active_open_index = max_open_files - 1;
    }

    fn noteRecentDocument(self: *App) void {
        if (self.current_path[0] == 0) return;
        _ = r4os.recent_documents.addOpenedFile(&self.ctx.sys, spanZ(self.current_path[0..]), "R4Code");
    }

    fn openInitialArg(self: *App) void {
        const raw = self.ctx.sys.argsRaw();
        if (raw[0] == 0) return;
        copyZPtr(self.selected_path[0..], raw);
        if (isSupportedSourceFile(spanZ(self.selected_path[0..]))) _ = self.loadFile(self.selected_path[0..]);
    }
};

const R4CodeSelfTest = struct {
    sys: r4os.r4sys.Context,
    log_buffer: [build_log_capacity]u8 = undefined,
    template_buffer: [template_buffer_capacity]u8 = undefined,
    source_template_buffer: [template_buffer_capacity]u8 = undefined,
    project_buffer: [template_buffer_capacity]u8 = undefined,
    source_buffer: [template_buffer_capacity]u8 = undefined,

    fn run(self: *R4CodeSelfTest) i32 {
        self.sys.println(version_text);
        self.sys.println("selftest");

        if (!self.writeTemplateProject(
            .c_console,
            "HELLOC",
            r4code_selftest_console_dir,
            r4code_selftest_console_src_dir,
            r4code_selftest_console_project_path,
            r4code_selftest_console_source_path,
            r4code_selftest_console_source,
        )) return self.fail("console project write failed");

        if (!self.buildAndCheck(
            "console",
            r4code_selftest_console_project_path,
            r4code_selftest_console_artifact_path,
            false,
        )) return 1;

        self.sys.println("R4CODE run console artifact");
        const console_id = self.sys.programSpawn(r4code_selftest_console_artifact_path, "", .console);
        if (console_id < 0) return self.fail("console artifact run failed");
        self.sys.sleepTicks(20);

        if (!writeFileSys(&self.sys, r4code_selftest_console_source_path, r4code_selftest_bad_source)) return self.fail("bad source write failed");
        const bad_rc = self.runBuildWorker("BUILD", r4code_selftest_console_project_path);
        self.printBuildLog();
        if (bad_rc == 0) return self.fail("bad source accepted");
        if (!self.logContains("R4CC error")) return self.fail("bad source diagnostic missing");

        if (!self.writeTemplateProject(
            .c_desktop_ok,
            "HELLOGUI",
            r4code_selftest_desktop_dir,
            r4code_selftest_desktop_src_dir,
            r4code_selftest_desktop_project_path,
            r4code_selftest_desktop_source_path,
            r4code_selftest_desktop_source,
        )) return self.fail("desktop project write failed");

        if (!self.buildAndCheck(
            "desktop",
            r4code_selftest_desktop_project_path,
            r4code_selftest_desktop_artifact_path,
            true,
        )) return 1;

        self.sys.println("R4CODE run desktop artifact");
        const desktop_id = self.sys.programSpawn(r4code_selftest_desktop_artifact_path, "", .gui);
        if (desktop_id < 0) return self.fail("desktop artifact run failed");
        if (self.sys.programRequestClose(@intCast(desktop_id)) != 0) return self.fail("desktop close request failed");
        self.sys.println("R4CODE desktop close requested");
        self.sys.sleepTicks(20);
        _ = self.sys.programKill(@intCast(desktop_id));

        self.sys.println("R4CODE result: OK");
        return 0;
    }

    fn writeTemplateProject(
        self: *R4CodeSelfTest,
        template: ProjectTemplate,
        project_name: []const u8,
        project_dir: []const u8,
        source_dir: []const u8,
        project_path: []const u8,
        source_path: []const u8,
        source_override: []const u8,
    ) bool {
        self.sys.write("R4CODE create project ");
        self.sys.println(project_name);
        _ = ensureDirectorySys(&self.sys, "C:\\TEMP");
        _ = ensureDirectorySys(&self.sys, "C:\\TEMP\\R4CODE");
        if (!ensureDirectorySys(&self.sys, project_dir)) return false;
        if (!ensureDirectorySys(&self.sys, source_dir)) return false;
        self.sys.println("R4CODE dirs OK");

        var project_template_path: [path_capacity]u8 = .{0} ** path_capacity;
        var source_template_path: [path_capacity]u8 = .{0} ** path_capacity;
        if (!templateFilePathFor(template, "module.R4MF.template", project_template_path[0..]) or
            !templateSourceFilePathFor(template, "main.c.template", source_template_path[0..]))
        {
            return false;
        }
        self.sys.println("R4CODE template paths OK");

        const project_template = readFileSys(&self.sys, spanZ(project_template_path[0..]), self.template_buffer[0..]) orelse return false;
        const source_template = readFileSys(&self.sys, spanZ(source_template_path[0..]), self.source_template_buffer[0..]) orelse return false;
        self.sys.println("R4CODE templates read OK");

        const project_result = renderProjectTemplateText(project_template, project_name, self.project_buffer[0..]);
        self.sys.println("R4CODE project template rendered");
        const source_result = renderProjectTemplateText(source_template, project_name, self.source_buffer[0..]);
        self.sys.println("R4CODE source template rendered");
        if (!project_result.ok or !source_result.ok) return false;
        self.sys.println("R4CODE parse generated project");
        var manifest_arena: [manifest_arena_capacity]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(manifest_arena[0..]);
        _ = r4os.r4mf.parse(fba.allocator(), project_path, project_result.bytes) catch return false;
        self.sys.println("R4CODE templates rendered OK");

        const source_bytes = if (source_override.len != 0) source_override else source_result.bytes;
        return writeFileSys(&self.sys, project_path, project_result.bytes) and
            writeFileSys(&self.sys, source_path, source_bytes);
    }

    fn buildAndCheck(self: *R4CodeSelfTest, label: []const u8, project_path: []const u8, artifact_path: []const u8, desktop: bool) bool {
        self.sys.write("R4CODE build ");
        self.sys.println(label);
        if (self.runBuildWorker("VALIDATE", project_path) != 0) return self.failCheck("validate failed");
        self.printBuildLog();
        if (self.runBuildWorker("PLAN", project_path) != 0) return self.failCheck("plan failed");
        self.printBuildLog();
        if (!self.logContains("R4MF_PLAN=1") or !self.logContains("plan result: OK")) return self.failCheck("canonical plan missing");
        const build_rc = self.runBuildWorker("BUILD", project_path);
        self.printBuildLog();
        if (build_rc != 0) return self.failCheck("build failed");
        if (!fileExistsSys(&self.sys, artifact_path)) return self.failCheck("artifact missing");
        if (!self.logContains("R4CC compile: OK") or !self.logContains("R4PACK package: OK")) return self.failCheck("build log incomplete");
        if (desktop) {
            if (!self.logContains("R4X_C_App_Desktop")) return self.failCheck("desktop profile missing");
            if (!self.logContains("import from R4MF: R4DESK:Query:1") or !self.logContains("import from R4MF: R4DRAW:Query:1")) return self.failCheck("desktop imports missing");
            if (!self.logContains("metadata: r4x.class=gui")) return self.failCheck("desktop gui metadata missing");
        } else {
            if (!self.logContains("R4X_C_App_Console")) return self.failCheck("console profile missing");
        }
        return true;
    }

    fn runBuildWorker(self: *R4CodeSelfTest, command: []const u8, project_path: []const u8) i32 {
        var args: [build_arg_capacity]u8 = .{0} ** build_arg_capacity;
        var len: usize = 0;
        if (!appendText(args[0..], &len, command) or
            !appendText(args[0..], &len, " ") or
            !appendText(args[0..], &len, project_path))
        {
            return -2;
        }
        self.sys.write("R4CODE build command: ");
        self.sys.println(command);
        _ = writeFileSys(&self.sys, r4build_log_path, "R4CODE build pending\r\n");
        const instance_id = self.sys.programSpawn(r4build_path, zptr(args[0..]), .console);
        if (instance_id < 0) return -2;
        return self.waitBuildResult(command);
    }

    fn waitBuildResult(self: *R4CodeSelfTest, command: []const u8) i32 {
        var attempt: usize = 0;
        while (attempt < 160) : (attempt += 1) {
            const read = self.sys.fileRead(r4build_log_path, self.log_buffer[0..]);
            if (read > 0) {
                const len: usize = @intCast(read);
                const text = self.log_buffer[0..len];
                if (equalsIgnoreCase(command, "VALIDATE")) {
                    if (contains(text, "validate result: OK")) return 0;
                    if (contains(text, "validate result: FAILED")) return 1;
                } else if (equalsIgnoreCase(command, "PLAN")) {
                    if (contains(text, "plan result: OK")) return 0;
                    if (contains(text, "plan result: FAILED")) return 1;
                } else {
                    if (contains(text, "build result: OK")) return 0;
                    if (contains(text, "build result: FAILED")) return 1;
                    if (contains(text, "build result: BLOCKED")) return 2;
                }
            }
            self.sys.sleepTicks(3);
        }
        return -3;
    }

    fn printBuildLog(self: *R4CodeSelfTest) void {
        const read = self.sys.fileRead(r4build_log_path, self.log_buffer[0..]);
        if (read <= 0) {
            self.sys.println("R4CODE build log: missing");
            return;
        }
        const len: usize = @intCast(read);
        self.sys.write(self.log_buffer[0..len]);
    }

    fn logContains(self: *R4CodeSelfTest, needle: []const u8) bool {
        const read = self.sys.fileRead(r4build_log_path, self.log_buffer[0..]);
        if (read <= 0) return false;
        const len: usize = @intCast(read);
        return contains(self.log_buffer[0..len], needle);
    }

    fn fail(self: *R4CodeSelfTest, message: []const u8) i32 {
        self.sys.write("R4CODE result: FAILED ");
        self.sys.println(message);
        return 1;
    }

    fn failCheck(self: *R4CodeSelfTest, message: []const u8) bool {
        _ = self.fail(message);
        return false;
    }
};

const r4code_selftest_console_dir = "C:\\TEMP\\R4CODE\\HELLOC";
const r4code_selftest_console_src_dir = "C:\\TEMP\\R4CODE\\HELLOC\\src";
const r4code_selftest_console_project_path = "C:\\TEMP\\R4CODE\\HELLOC\\module.R4MF";
const r4code_selftest_console_source_path = "C:\\TEMP\\R4CODE\\HELLOC\\src\\main.c";
const r4code_selftest_console_artifact_path = "C:\\TEMP\\R4CODE\\HELLOC\\out\\HELLOC.R4X";
const r4code_selftest_desktop_dir = "C:\\TEMP\\R4CODE\\HELLOGUI";
const r4code_selftest_desktop_src_dir = "C:\\TEMP\\R4CODE\\HELLOGUI\\src";
const r4code_selftest_desktop_project_path = "C:\\TEMP\\R4CODE\\HELLOGUI\\module.R4MF";
const r4code_selftest_desktop_source_path = "C:\\TEMP\\R4CODE\\HELLOGUI\\src\\main.c";
const r4code_selftest_desktop_artifact_path = "C:\\TEMP\\R4CODE\\HELLOGUI\\out\\HELLOGUI.R4X";

const r4code_selftest_console_source =
    \\#include <r4os/r4os.h>
    \\
    \\R4OS_TEXT(hello_message, "HELLO from R4CODE edited source");
    \\
    \\int32_t r4_app_main(R4App *app)
    \\{
    \\    return r4sys_write_line(&app->system, hello_message);
    \\}
    \\
;

const r4code_selftest_desktop_source =
    \\#include <r4os/r4os.h>
    \\
    \\R4OS_TEXT(window_title, "HELLOGUI");
    \\R4OS_TEXT(ok_label, "OK");
    \\R4OS_TEXT(message, "HELLO from R4CODE Desktop OK");
    \\
    \\int32_t r4_app_main(R4App *app)
    \\{
    \\    R4Timer timers[1] = {{0}}; R4Window window; R4PaintContext paint;
    \\    if (!r4_window_open(app, timers, 1, &window)) return R4OS_ERR_NO_GROUP;
    \\    r4_window_set_title(&window, window_title); r4_window_set_minimum_size(&window, 260, 140);
    \\    if (!r4_window_begin_paint(&window, &paint)) return R4OS_ERR_NO_FN;
    \\    R4Canvas canvas = r4_paint_canvas(&paint);
    \\    r4_canvas_clear(canvas, 0x00C0C0C0); r4_canvas_rect(canvas, 84, 78, 72, 24, 0x00C0C0C0);
    \\    r4_canvas_text(canvas, 58, 50, message, 0x000000, 0x00FFFFFF); r4_canvas_text(canvas, 112, 86, ok_label, 0x000000, 0x00C0C0C0); r4_paint_present(&paint);
    \\    for (;;) { R4MessageNext next = r4_window_wait_message(&window, r4_timeout_forever());
    \\        if (next.state == R4_MESSAGE_NEXT_FAILED) return next.raw_code;
    \\        if (next.message.kind == R4_MESSAGE_CLOSE) return 0;
    \\        if (next.message.kind == R4_MESSAGE_MOUSE && next.message.value.mouse.action == R4_MOUSE_UP) return 0; }
    \\}
    \\
;

const r4code_selftest_bad_source =
    \\#include <r4os/r4os.h>
    \\
    \\int32_t r4_app_main(R4App *app)
    \\{
    \\    return r4sys_write_line(&app->system, missing_message);
    \\}
    \\
;

fn buildAppMenus(out: *AppMenus, project_collapsed: bool) []const r4os.gui.MenubarMenu {
    out.file_items = .{
        .{ .text = "New Source File", .id = @intFromEnum(Command.file_new), .shortcut = "Ctrl+N" },
        .{ .text = "New C Console Project", .id = @intFromEnum(Command.file_new_c_console_project) },
        .{ .text = "New C Desktop OK Project", .id = @intFromEnum(Command.file_new_c_desktop_ok_project) },
        .{ .text = "Open Source", .id = @intFromEnum(Command.file_open), .shortcut = "Ctrl+O" },
        .{ .text = "Open Folder", .id = @intFromEnum(Command.file_open_folder) },
        .{ .text = "Save", .id = @intFromEnum(Command.file_save), .shortcut = "Ctrl+S", .separator_before = true },
        .{ .text = "Save As", .id = @intFromEnum(Command.file_save_as) },
        .{ .text = "Exit", .id = @intFromEnum(Command.file_exit), .separator_before = true },
    };
    out.edit_items = .{
        .{ .text = "Cut", .id = @intFromEnum(Command.edit_cut), .shortcut = "Ctrl+X" },
        .{ .text = "Copy", .id = @intFromEnum(Command.edit_copy), .shortcut = "Ctrl+C" },
        .{ .text = "Paste", .id = @intFromEnum(Command.edit_paste), .shortcut = "Ctrl+V" },
    };
    out.view_items = .{
        .{ .text = if (project_collapsed) "Show Project Panel" else "Hide Project Panel", .id = @intFromEnum(Command.view_project_panel) },
    };
    out.build_items = .{
        .{ .text = "Build", .id = @intFromEnum(Command.build_build) },
        .{ .text = "Run", .id = @intFromEnum(Command.build_run) },
    };
    out.menus = .{
        .{ .text = "File", .items = out.file_items[0..] },
        .{ .text = "Edit", .items = out.edit_items[0..] },
        .{ .text = "View", .items = out.view_items[0..] },
        .{ .text = "Build", .items = out.build_items[0..] },
    };
    return out.menus[0..];
}

fn zptr(buffer: []const u8) [*:0]const u8 {
    return @ptrCast(buffer.ptr);
}

fn zSlice(ptr: [*:0]const u8) []const u8 {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
}

fn zero(buffer: []u8) void {
    @memset(buffer, 0);
}

fn setZ(buffer: []u8, text: []const u8) void {
    zero(buffer);
    if (buffer.len == 0) return;
    const len = @min(buffer.len - 1, text.len);
    if (len > 0) @memcpy(buffer[0..len], text[0..len]);
    buffer[len] = 0;
}

fn setZResult(buffer: []u8, text: []const u8) bool {
    if (text.len + 1 > buffer.len) return false;
    setZ(buffer, text);
    return true;
}

fn copyZ(dest: []u8, source: []const u8) void {
    setZ(dest, spanZ(source));
}

fn copyZPtr(dest: []u8, source: [*:0]const u8) void {
    zero(dest);
    var i: usize = 0;
    while (i + 1 < dest.len and source[i] != 0) : (i += 1) dest[i] = source[i];
    if (dest.len > 0) dest[i] = 0;
}

fn appendZChar(buffer: []u8, ch: u8) void {
    const len = zlen(buffer);
    if (len + 1 >= buffer.len) return;
    buffer[len] = ch;
    buffer[len + 1] = 0;
}

fn backspaceZ(buffer: []u8, min_len: usize) void {
    const len = zlen(buffer);
    if (len <= min_len) return;
    buffer[len - 1] = 0;
}

fn zlen(buffer: []const u8) usize {
    var len: usize = 0;
    while (len < buffer.len and buffer[len] != 0) : (len += 1) {}
    return len;
}

fn spanZ(buffer: []const u8) []const u8 {
    return buffer[0..zlen(buffer)];
}

fn baseName(path: []const u8) []const u8 {
    var start: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '\\' or path[i] == '/') start = i + 1;
    }
    return path[start..];
}

fn buildPath(dir_buffer: []const u8, name_buffer: []const u8, out: []u8) bool {
    const dir = spanZ(dir_buffer);
    const name = spanZ(name_buffer);
    return buildPathText(dir, name, out);
}

fn buildPathText(dir: []const u8, name: []const u8, out: []u8) bool {
    if (name.len == 0 or out.len == 0) return false;
    zero(out);
    if (isAbsolutePath(name)) {
        if (name.len + 1 > out.len) return false;
        @memcpy(out[0..name.len], name);
        out[name.len] = 0;
        return true;
    }
    var len: usize = @min(dir.len, out.len - 1);
    if (len > 0) @memcpy(out[0..len], dir[0..len]);
    if (len > 0 and out[len - 1] != '\\' and out[len - 1] != '/') {
        if (len + 1 >= out.len) return false;
        out[len] = '\\';
        len += 1;
    }
    if (len + name.len + 1 > out.len) return false;
    @memcpy(out[len .. len + name.len], name);
    out[len + name.len] = 0;
    return true;
}

fn buildArtifactPathFor(project_name: []const u8, out: []u8) bool {
    zero(out);
    var len: usize = 0;
    return appendText(out, &len, "out/") and
        appendText(out, &len, project_name) and
        appendText(out, &len, ".R4X");
}

fn templateFilePathFor(template: ProjectTemplate, file_name: []const u8, out: []u8) bool {
    var template_dir: [path_capacity]u8 = .{0} ** path_capacity;
    return buildPathText(sdk_templates_root, template.folder(), template_dir[0..]) and
        buildPathText(spanZ(template_dir[0..]), file_name, out);
}

fn templateSourceFilePathFor(template: ProjectTemplate, file_name: []const u8, out: []u8) bool {
    var template_dir: [path_capacity]u8 = .{0} ** path_capacity;
    var src_dir: [path_capacity]u8 = .{0} ** path_capacity;
    return buildPathText(sdk_templates_root, template.folder(), template_dir[0..]) and
        buildPathText(spanZ(template_dir[0..]), "src", src_dir[0..]) and
        buildPathText(spanZ(src_dir[0..]), file_name, out);
}

fn setDirFromSpecificPath(path: []const u8, out: []u8) void {
    var last_sep: ?usize = null;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '\\' or path[i] == '/') last_sep = i;
    }
    if (last_sep) |sep| {
        setZ(out, path[0 .. sep + 1]);
    } else {
        setZ(out, "C:\\");
    }
}

fn makeProjectFileName(out: []u8) bool {
    zero(out);
    var len: usize = 0;
    if (!appendText(out, &len, "module.R4MF")) return false;
    if (len >= out.len) return false;
    out[len] = 0;
    return true;
}

fn renderProjectTemplateText(template: []const u8, project_name: []const u8, out: []u8) TemplateRenderResult {
    const token = "{ProjectName}";
    zero(out);
    var len: usize = 0;
    var index: usize = 0;
    while (index < template.len) {
        if (index + token.len <= template.len and equalsBytes(template[index .. index + token.len], token)) {
            if (!appendText(out, &len, project_name)) return .{ .bytes = out[0..0], .ok = false };
            index += token.len;
        } else {
            if (len + 2 > out.len) return .{ .bytes = out[0..0], .ok = false };
            out[len] = template[index];
            len += 1;
            out[len] = 0;
            index += 1;
        }
    }
    return .{ .bytes = out[0..len], .ok = true };
}

fn appendText(out: []u8, len: *usize, text: []const u8) bool {
    if (len.* + text.len + 1 > out.len) return false;
    if (text.len > 0) @memcpy(out[len.* .. len.* + text.len], text);
    len.* += text.len;
    out[len.*] = 0;
    return true;
}

fn isAbsolutePath(path: []const u8) bool {
    if (path.len >= 2 and path[1] == ':') return true;
    return path.len > 0 and (path[0] == '\\' or path[0] == '/');
}

fn validProjectName(name: []const u8) bool {
    if (name.len == 0 or name.len >= project_name_capacity) return false;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        const ch = name[i];
        if ((ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_') continue;
        return false;
    }
    return true;
}

fn isFileNameChar(ch: u8) bool {
    if (ch < 0x20 or ch >= 0x7F) return false;
    return ch != '\\' and ch != '/' and ch != ':' and ch != '*' and ch != '?' and ch != '"' and ch != '<' and ch != '>' and ch != '|';
}

fn isTextEditingKey(key: u8) bool {
    return (key >= 0x20 and key < 0x7F) or key == r4os.gui.Key.backspace or key == r4os.gui.Key.delete or key == r4os.gui.Key.enter or key == r4os.gui.Key.tab;
}

fn isSupportedSourceFile(path: []const u8) bool {
    return endsWithIgnoreCase(path, ".c") or endsWithIgnoreCase(path, ".zig") or isR4MFFile(path) or isR4CPFile(path) or endsWithIgnoreCase(path, ".txt");
}

fn isR4MFFile(path: []const u8) bool {
    return endsWithIgnoreCase(path, ".r4mf");
}

fn isR4CPFile(path: []const u8) bool {
    return endsWithIgnoreCase(path, ".r4cp");
}

fn hasSelftestSwitch(args: []const u8) bool {
    return equalsIgnoreCase(args, "/SELFTEST") or equalsIgnoreCase(args, "SELFTEST");
}

fn trim(value: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = value.len;
    while (start < end and isSpace(value[start])) : (start += 1) {}
    while (end > start and isSpace(value[end - 1])) : (end -= 1) {}
    return value[start..end];
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (equalsBytes(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn equalsBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn writeFileSys(sys: *const r4os.r4sys.Context, path: []const u8, data: []const u8) bool {
    var path_z: [path_capacity]u8 = .{0} ** path_capacity;
    if (!setZResult(path_z[0..], path)) return false;
    const written = sys.fileWrite(zptr(path_z[0..]), data);
    return written >= 0 and @as(usize, @intCast(written)) == data.len;
}

fn readFileSys(sys: *const r4os.r4sys.Context, path: []const u8, out: []u8) ?[]const u8 {
    var path_z: [path_capacity]u8 = .{0} ** path_capacity;
    if (!setZResult(path_z[0..], path)) return null;
    const read = sys.fileRead(zptr(path_z[0..]), out);
    if (read <= 0) return null;
    const len: usize = @intCast(read);
    if (len >= out.len) return null;
    return out[0..len];
}

fn fileExistsSys(sys: *const r4os.r4sys.Context, path: []const u8) bool {
    var path_z: [path_capacity]u8 = .{0} ** path_capacity;
    if (!setZResult(path_z[0..], path)) return false;
    if (sys.fileInfo(zptr(path_z[0..]))) |info| return info.exists != 0 and info.is_dir == 0;
    return false;
}

fn dirExistsSys(sys: *const r4os.r4sys.Context, path: []const u8) bool {
    var path_z: [path_capacity]u8 = .{0} ** path_capacity;
    if (!setZResult(path_z[0..], path)) return false;
    if (sys.fileInfo(zptr(path_z[0..]))) |info| return info.exists != 0 and info.is_dir != 0;
    return false;
}

fn ensureDirectorySys(sys: *const r4os.r4sys.Context, path: []const u8) bool {
    if (dirExistsSys(sys, path)) return true;
    var path_z: [path_capacity]u8 = .{0} ** path_capacity;
    if (!setZResult(path_z[0..], path)) return false;
    _ = sys.dirCreate(zptr(path_z[0..]));
    return dirExistsSys(sys, path);
}

fn endsWithIgnoreCase(value: []const u8, suffix: []const u8) bool {
    if (suffix.len > value.len) return false;
    return equalsIgnoreCase(value[value.len - suffix.len ..], suffix);
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (asciiLower(a[i]) != asciiLower(b[i])) return false;
    }
    return true;
}

fn asciiLower(ch: u8) u8 {
    if (ch >= 'A' and ch <= 'Z') return ch + ('a' - 'A');
    return ch;
}

fn drawFrame(canvas: r4os.gui.Canvas, rect: r4os.gui.Rect, fill: u32) void {
    _ = canvas.rect(rect, palette.face_shadow);
    _ = canvas.rect(.{ .x = rect.x + 1, .y = rect.y + 1, .w = rect.w - 2, .h = rect.h - 2 }, palette.face_light);
    _ = canvas.rect(.{ .x = rect.x + 2, .y = rect.y + 2, .w = rect.w - 4, .h = rect.h - 4 }, fill);
}

fn clampI32(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}
