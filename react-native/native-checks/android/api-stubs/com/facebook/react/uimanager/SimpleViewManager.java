// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.uimanager;
import android.view.View;
public abstract class SimpleViewManager<T extends View> extends ViewManager<T, LayoutShadowNode> {}
