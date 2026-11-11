package com.local.adbhide;

import java.lang.reflect.Method;
import java.util.List;

import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * v1.1
 * 在 system_server 的 SettingsProvider 里伪造 adb_enabled=0。
 * 好处：Momo 等检测器自己的进程完全不被注入，看不到任何注入痕迹，
 *      但它读到的调试开关是 0；而系统内部（uid 1000）读到的仍是真实值，adbd 不受影响。
 */
public class MainHook implements IXposedHookLoadPackage {

    private static final String KEY = "adb_enabled";
    private static final String TAG = "ADBHide: ";

    /** 这些 uid 读到真实值：system / root / shell，保证 adbd 与开发者选项正常 */
    private static boolean keepReal(int uid) {
        return uid == 1000 || uid == 0 || uid == 2000;
    }

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lp) {
        try {
            String p = lp.processName;
            if ("android".equals(p) || "system".equals(p)) {
                hookProvider(lp);
            }
            hookSettingsGlobal(lp);
        } catch (Throwable t) {
            XposedBridge.log(TAG + "init failed: " + t);
        }
    }

    /** system_server：拦 SettingsProvider 的 query / call */
    private void hookProvider(XC_LoadPackage.LoadPackageParam lp) {
        Class<?> sp;
        try {
            sp = XposedHelpers.findClass("com.android.providers.settings.SettingsProvider", lp.classLoader);
        } catch (Throwable t) {
            XposedBridge.log(TAG + "SettingsProvider not found: " + t);
            return;
        }

        XposedBridge.hookAllMethods(sp, "query", new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                try {
                    if (param.args.length < 1 || !(param.args[0] instanceof Uri)) return;
                    Uri uri = (Uri) param.args[0];
                    List<String> seg = uri.getPathSegments();
                    if (seg == null || seg.size() != 2) return;
                    if (!"global".equals(seg.get(0)) || !KEY.equals(seg.get(1))) return;
                    if (keepReal(Binder.getCallingUid())) return;

                    MatrixCursor c = new MatrixCursor(new String[]{"value"});
                    c.addRow(new Object[]{"0"});
                    param.setResult(c);
                } catch (Throwable ignored) {
                }
            }
        });

        XposedBridge.hookAllMethods(sp, "call", new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                try {
                    if (param.args.length < 2) return;
                    Object method = param.args[0];
                    Object name = param.args[1];
                    if (!(method instanceof String) || !(name instanceof String)) return;
                    if (!KEY.equals(name)) return;
                    String m = (String) method;
                    if (!"GET_global".equals(m) && !"GET_secure".equals(m) && !"GET_system".equals(m)) return;
                    if (keepReal(Binder.getCallingUid())) return;

                    Bundle b = new Bundle();
                    b.putString("value", "0");
                    param.setResult(b);
                } catch (Throwable ignored) {
                }
            }
        });

        XposedBridge.log(TAG + "provider hooks installed");
    }

    /** 兜底：万一某进程内直接调 Settings.Global（不走 provider） */
    private void hookSettingsGlobal(XC_LoadPackage.LoadPackageParam lp) {
        Class<?> global;
        try {
            global = XposedHelpers.findClass("android.provider.Settings$Global", lp.classLoader);
        } catch (Throwable t) {
            return;
        }

        XC_MethodHook hook = new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                if (param.args == null || param.args.length < 2) return;
                Object key = param.args[1];
                if (!KEY.equals(key)) return;

                Class<?> ret = ((Method) param.method).getReturnType();
                if (ret == int.class) {
                    param.setResult(0);
                } else if (ret == long.class) {
                    param.setResult(0L);
                } else if (ret == float.class) {
                    param.setResult(0f);
                } else if (ret == boolean.class) {
                    param.setResult(false);
                } else {
                    param.setResult("0");
                }
            }
        };

        for (String m : new String[]{"getInt", "getLong", "getFloat", "getString", "getBoolean"}) {
            try {
                XposedBridge.hookAllMethods(global, m, hook);
            } catch (Throwable ignored) {
            }
        }
    }
}
