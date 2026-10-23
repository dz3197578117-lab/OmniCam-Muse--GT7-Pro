package local.jiege.hook.common;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import org.json.JSONObject;

/**
 * Per-device feature switches.
 *
 * assets/device.json is copied from device-profiles/&lt;name&gt;.json by
 * {@code gradlew -Pdevice=<name>}; it lists one boolean per feature. The key names match
 * module/device.json, which the init scripts read with grep, so the app and the mount scripts
 * always agree on what this device supports.
 *
 * This branch targets the realme GT7 Pro, whose profile keeps most features off until they are
 * verified, so a build without a readable profile installs nothing rather than guessing: this
 * phone has no Hasselblad pipeline, and hooking it blindly is how a camera stops opening. A key
 * the profile does not mention is still on, so adding a feature means adding one line to one file.
 */
public final class DeviceProfile {
    private static final String ASSET = "assets/device.json";

    /** null until parsed; an empty map means "parsed, no features listed". */
    private static volatile Map<String, Boolean> flags;
    private static volatile boolean present;
    private static volatile String device = "gt7pro";

    private DeviceProfile() {}

    /** True when the feature is on for this device; false when there is no profile at all. */
    public static boolean on(String feature) {
        Map<String, Boolean> all = load();
        if (!present) return false;
        Boolean value = all.get(feature);
        return value == null || value;
    }

    /** Profile name, e.g. "gt7pro". */
    public static String device() {
        return device;
    }

    private static Map<String, Boolean> load() {
        Map<String, Boolean> loaded = flags;
        if (loaded != null) return loaded;
        synchronized (DeviceProfile.class) {
            if (flags != null) return flags;
            Map<String, Boolean> parsed = new LinkedHashMap<>();
            String name = device;
            try {
                JSONObject root = new JSONObject(read());
                name = root.optString("device", name);
                JSONObject features = root.optJSONObject("features");
                if (features != null) {
                    for (Iterator<String> it = features.keys(); it.hasNext(); ) {
                        String key = it.next();
                        parsed.put(key, features.optBoolean(key, true));
                    }
                }
                present = true;
            } catch (Throwable error) {
                // No profile inside the APK, or an unreadable one: install nothing.
                Log.i("DeviceProfile", "no device profile, every feature stays off: " + error);
            }
            device = name;
            flags = Collections.unmodifiableMap(parsed);
            return flags;
        }
    }

    private static String read() throws Exception {
        InputStream in = DeviceProfile.class.getClassLoader().getResourceAsStream(ASSET);
        if (in != null) return text(in);
        String path = Symbols.modulePath();
        if (path == null) throw new IllegalStateException(ASSET + " not readable (no module path)");
        try (java.util.zip.ZipFile apk = new java.util.zip.ZipFile(path)) {
            java.util.zip.ZipEntry entry = apk.getEntry(ASSET);
            if (entry == null) throw new IllegalStateException(ASSET + " missing from " + path);
            return text(apk.getInputStream(entry));
        }
    }

    private static String text(InputStream in) throws Exception {
        try (InputStream input = in) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            for (int n; (n = input.read(buffer)) > 0; ) out.write(buffer, 0, n);
            return new String(out.toByteArray(), "UTF-8");
        }
    }
}
