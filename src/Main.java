import javafx.application.Application;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.stage.DirectoryChooser;
import javafx.stage.Stage;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.prefs.Preferences;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main extends Application {

    private static final Pattern PROGRESS = Pattern.compile("\\[download\\]\\s+(\\d{1,3}(?:\\.\\d+)?)%");

    private final Preferences prefs = Preferences.userNodeForPackage(Main.class);
    private volatile Process current;

    @Override
    public void start(Stage stage) {

        Label titleLabel = new Label("stillit");
        titleLabel.getStyleClass().add("title-label");

        TextField urlField = new TextField();
        urlField.setPromptText("Paste video or playlist URL here");

        TextField destField = new TextField();
        destField.setPromptText("Select download folder");
        destField.setEditable(false);
        destField.setText(prefs.get("dest", defaultDownloadDir()));
        HBox.setHgrow(destField, Priority.ALWAYS);

        Button browseBtn = new Button("Browse");
        browseBtn.setOnAction(e -> {
            DirectoryChooser chooser = new DirectoryChooser();
            chooser.setTitle("Select download folder");
            File start = new File(destField.getText());
            if (start.isDirectory()) chooser.setInitialDirectory(start);
            File selected = chooser.showDialog(stage);
            if (selected != null) {
                destField.setText(selected.getAbsolutePath());
                prefs.put("dest", selected.getAbsolutePath());
            }
        });
        HBox destRow = new HBox(8, destField, browseBtn);

        ComboBox<String> qualityBox = new ComboBox<>();
        qualityBox.getItems().addAll("Best", "1080p", "720p", "480p", "Audio Only");
        qualityBox.setValue("Best");
        qualityBox.setMaxWidth(Double.MAX_VALUE);

        ComboBox<String> typeBox = new ComboBox<>();
        typeBox.getItems().addAll("mp4", "mkv", "mp3");
        typeBox.setValue("mp4");
        typeBox.setMaxWidth(Double.MAX_VALUE);

        qualityBox.valueProperty().addListener((o, old, val) -> {
            if ("Audio Only".equals(val)) typeBox.setValue("mp3");
            else if ("mp3".equals(typeBox.getValue())) typeBox.setValue("mp4");
        });
        typeBox.valueProperty().addListener((o, old, val) -> {
            if ("mp3".equals(val)) qualityBox.setValue("Audio Only");
            else if ("Audio Only".equals(qualityBox.getValue())) qualityBox.setValue("Best");
        });

        CheckBox playlistBox = new CheckBox("Download whole playlist");

        GridPane options = new GridPane();
        options.setHgap(8);
        options.setVgap(8);
        options.add(new Label("Quality"), 0, 0);
        options.add(new Label("Format"), 1, 0);
        options.add(qualityBox, 0, 1);
        options.add(typeBox, 1, 1);
        ColumnConstraints half = new ColumnConstraints();
        half.setPercentWidth(50);
        options.getColumnConstraints().addAll(half, half);

        Button downloadBtn = new Button("Download");
        downloadBtn.setMaxWidth(Double.MAX_VALUE);
        downloadBtn.setDefaultButton(true);
        Button cancelBtn = new Button("Cancel");
        cancelBtn.setDisable(true);
        HBox.setHgrow(downloadBtn, Priority.ALWAYS);
        HBox actionRow = new HBox(8, downloadBtn, cancelBtn);

        ProgressBar progress = new ProgressBar(0);
        progress.setMaxWidth(Double.MAX_VALUE);

        Label status = new Label("Ready");
        status.getStyleClass().add("status-label");

        TextArea logArea = new TextArea();
        logArea.setEditable(false);
        logArea.setWrapText(true);
        logArea.setPrefHeight(220);
        VBox.setVgrow(logArea, Priority.ALWAYS);

        downloadBtn.setOnAction(e -> {
            String url = urlField.getText().trim();
            String dest = destField.getText().trim();

            if (url.isEmpty() || dest.isEmpty()) {
                new Alert(Alert.AlertType.ERROR,
                        "Please provide a URL and select a download folder.").showAndWait();
                return;
            }
            File destDir = new File(dest);
            if (!destDir.isDirectory() && !destDir.mkdirs()) {
                new Alert(Alert.AlertType.ERROR,
                        "Download folder does not exist and could not be created:\n" + dest).showAndWait();
                return;
            }

            File ytdlp = findYtDlp();
            if (ytdlp == null) {
                new Alert(Alert.AlertType.ERROR,
                        "Could not find yt-dlp.exe.\n\nIt should sit next to this application, "
                                + "or be available on your PATH.").showAndWait();
                return;
            }

            List<String> cmd = buildCommand(ytdlp, url, destDir,
                    qualityBox.getValue(), typeBox.getValue(), playlistBox.isSelected());

            logArea.clear();
            logArea.appendText("> " + String.join(" ", cmd) + "\n\n");
            progress.setProgress(0);
            status.setText("Downloading...");
            downloadBtn.setDisable(true);
            cancelBtn.setDisable(false);

            Thread worker = new Thread(() -> runDownload(cmd, logArea, progress, status,
                    downloadBtn, cancelBtn), "yt-dlp-runner");
            worker.setDaemon(true);
            worker.start();
        });

        cancelBtn.setOnAction(e -> {
            Process p = current;
            if (p != null) {
                p.descendants().forEach(ProcessHandle::destroy);
                p.destroy();
                status.setText("Cancelled");
            }
        });

        VBox layout = new VBox(10,
                titleLabel,
                new Label("Video URL"), urlField,
                new Label("Save to"), destRow,
                options,
                playlistBox,
                actionRow,
                progress,
                status,
                logArea);
        layout.setPadding(new Insets(16));
        layout.setAlignment(Pos.TOP_LEFT);

        Scene scene = new Scene(layout, 560, 640);
        var css = getClass().getResource("style.css");
        if (css != null) scene.getStylesheets().add(css.toExternalForm());

        stage.setTitle("stillit");
        stage.setMinWidth(480);
        stage.setMinHeight(560);
        stage.setScene(scene);
        stage.setOnCloseRequest(e -> {
            Process p = current;
            if (p != null) {
                p.descendants().forEach(ProcessHandle::destroy);
                p.destroy();
            }
        });
        stage.show();
    }

    private List<String> buildCommand(File ytdlp, String url, File destDir,
                                      String quality, String type, boolean playlist) {
        boolean audioOnly = "Audio Only".equals(quality) || "mp3".equals(type);

        List<String> cmd = new ArrayList<>();
        cmd.add(ytdlp.getAbsolutePath());
        cmd.add("--newline");
        cmd.add("--ignore-config");
        cmd.add(playlist ? "--yes-playlist" : "--no-playlist");

        File ffmpegDir = findFfmpegDir();
        if (ffmpegDir != null) {
            cmd.add("--ffmpeg-location");
            cmd.add(ffmpegDir.getAbsolutePath());
        }

        if (audioOnly) {
            cmd.add("-f");
            cmd.add("ba/b");
            cmd.add("-x");
            cmd.add("--audio-format");
            cmd.add("mp3");
            cmd.add("--audio-quality");
            cmd.add("0");
        } else {
            cmd.add("-f");
            if ("Best".equals(quality)) {
                cmd.add("bv*+ba/b");
            } else {
                String h = quality.replace("p", "");
                cmd.add("bv*[height<=" + h + "]+ba/b[height<=" + h + "]/b");
            }
            cmd.add("--merge-output-format");
            cmd.add(type);
        }

        cmd.add("-o");
        cmd.add(new File(destDir, "%(title)s.%(ext)s").getPath());
        cmd.add(url);
        return cmd;
    }

    private void runDownload(List<String> cmd, TextArea logArea, ProgressBar progress,
                             Label status, Button downloadBtn, Button cancelBtn) {
        int exit = -1;
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Map<String, String> env = pb.environment();
            String pathKey = env.keySet().stream()
                    .filter(k -> k.equalsIgnoreCase("PATH"))
                    .findFirst().orElse("PATH");
            env.put(pathKey, appDir().getAbsolutePath()
                    + File.pathSeparator + env.getOrDefault(pathKey, ""));
            Process p = pb.start();
            current = p;

            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    final String text = line;
                    Matcher m = PROGRESS.matcher(text);
                    final double pct = m.find() ? Double.parseDouble(m.group(1)) / 100.0 : -1;
                    Platform.runLater(() -> {
                        logArea.appendText(text + "\n");
                        if (pct >= 0) progress.setProgress(pct);
                    });
                }
            }
            exit = p.waitFor();
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
        } catch (Exception ex) {
            final String msg = String.valueOf(ex.getMessage());
            Platform.runLater(() -> logArea.appendText("\nERROR: " + msg + "\n"));
        } finally {
            current = null;
            final int code = exit;
            Platform.runLater(() -> {
                downloadBtn.setDisable(false);
                cancelBtn.setDisable(true);
                if (code == 0) {
                    progress.setProgress(1);
                    status.setText("Done");
                } else {
                    status.setText("Failed (exit code " + code + ") - see log below");
                }
            });
        }
    }

    private static File appDir() {
        String dir = System.getProperty("app.dir");
        if (dir != null) return new File(dir);
        try {
            Path jar = Paths.get(Main.class.getProtectionDomain()
                    .getCodeSource().getLocation().toURI());
            return jar.getParent().toFile();
        } catch (Exception ex) {
            return new File(".").getAbsoluteFile();
        }
    }

    private static File findYtDlp() {
        List<File> candidates = new ArrayList<>();
        File dir = appDir();
        candidates.add(new File(dir, "yt-dlp.exe"));
        candidates.add(new File(dir, "bin/yt-dlp.exe"));
        if (dir.getParentFile() != null) {
            candidates.add(new File(dir.getParentFile(), "yt-dlp.exe"));
        }
        candidates.add(new File(System.getProperty("user.home"), "yt-dlp.exe"));
        for (File f : candidates) {
            if (f.isFile()) return f;
        }
        return onPath("yt-dlp.exe");
    }

    private static File findFfmpegDir() {
        File dir = appDir();
        List<File> candidates = new ArrayList<>();
        candidates.add(new File(dir, "ffmpeg.exe"));
        candidates.add(new File(dir, "bin/ffmpeg.exe"));
        if (dir.getParentFile() != null) {
            candidates.add(new File(dir.getParentFile(), "ffmpeg.exe"));
        }
        for (File f : candidates) {
            if (f.isFile()) return f.getParentFile();
        }
        File onPath = onPath("ffmpeg.exe");
        return onPath == null ? null : onPath.getParentFile();
    }

    private static File onPath(String exe) {
        String path = System.getenv("PATH");
        if (path == null) return null;
        for (String entry : path.split(File.pathSeparator)) {
            File f = new File(entry, exe);
            if (f.isFile()) return f;
        }
        return null;
    }

    private static String defaultDownloadDir() {
        File downloads = new File(System.getProperty("user.home"), "Downloads");
        return downloads.isDirectory()
                ? downloads.getAbsolutePath()
                : System.getProperty("user.home");
    }

    public static void main(String[] args) {
        launch(args);
    }
}
