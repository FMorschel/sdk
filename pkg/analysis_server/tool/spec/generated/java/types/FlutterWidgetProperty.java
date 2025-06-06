/*
 * Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
 * for details. All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 *
 * This file has been automatically generated. Please do not edit it manually.
 * To regenerate the file, use the script "pkg/analysis_server/tool/spec/generate_files".
 */
package org.dartlang.analysis.server.protocol;

import java.util.Arrays;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;
import com.google.dart.server.utilities.general.JsonUtilities;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;

/**
 * A property of a Flutter widget.
 *
 * @coverage dart.server.generated.types
 */
@SuppressWarnings("unused")
public class FlutterWidgetProperty {

  public static final List<FlutterWidgetProperty> EMPTY_LIST = List.of();

  /**
   * The documentation of the property to show to the user. Omitted if the server does not know the
   * documentation, e.g. because the corresponding field is not documented.
   */
  private final String documentation;

  /**
   * If the value of this property is set, the Dart code of the expression of this property.
   */
  private final String expression;

  /**
   * The unique identifier of the property, must be passed back to the server when updating the
   * property value. Identifiers become invalid on any source code change.
   */
  private final int id;

  /**
   * True if the property is required, e.g. because it corresponds to a required parameter of a
   * constructor.
   */
  private final boolean isRequired;

  /**
   * If the property expression is a concrete value (e.g. a literal, or an enum constant), then it is
   * safe to replace the expression with another concrete value. In this case this field is true.
   * Otherwise, for example when the expression is a reference to a field, so that its value is
   * provided from outside, this field is false.
   */
  private final boolean isSafeToUpdate;

  /**
   * The name of the property to display to the user.
   */
  private final String name;

  /**
   * The list of children properties, if any. For example any property of type
   * <code>EdgeInsets</code> will have four children properties of type <code>double</code> - left /
   * top / right / bottom.
   */
  private final List<FlutterWidgetProperty> children;

  /**
   * The editor that should be used by the client. This field is omitted if the server does not know
   * the editor for this property, for example because it does not have one of the supported types.
   */
  private final FlutterWidgetPropertyEditor editor;

  /**
   * If the expression is set, and the server knows the value of the expression, this field is set.
   */
  private final FlutterWidgetPropertyValue value;

  /**
   * Constructor for {@link FlutterWidgetProperty}.
   */
  public FlutterWidgetProperty(String documentation, String expression, int id, boolean isRequired, boolean isSafeToUpdate, String name, List<FlutterWidgetProperty> children, FlutterWidgetPropertyEditor editor, FlutterWidgetPropertyValue value) {
    this.documentation = documentation;
    this.expression = expression;
    this.id = id;
    this.isRequired = isRequired;
    this.isSafeToUpdate = isSafeToUpdate;
    this.name = name;
    this.children = children;
    this.editor = editor;
    this.value = value;
  }

  @Override
  public boolean equals(Object obj) {
    if (obj instanceof FlutterWidgetProperty other) {
      return
        Objects.equals(other.documentation, documentation) &&
        Objects.equals(other.expression, expression) &&
        other.id == id &&
        other.isRequired == isRequired &&
        other.isSafeToUpdate == isSafeToUpdate &&
        Objects.equals(other.name, name) &&
        Objects.equals(other.children, children) &&
        Objects.equals(other.editor, editor) &&
        Objects.equals(other.value, value);
    }
    return false;
  }

  public static FlutterWidgetProperty fromJson(JsonObject jsonObject) {
    String documentation = jsonObject.get("documentation") == null ? null : jsonObject.get("documentation").getAsString();
    String expression = jsonObject.get("expression") == null ? null : jsonObject.get("expression").getAsString();
    int id = jsonObject.get("id").getAsInt();
    boolean isRequired = jsonObject.get("isRequired").getAsBoolean();
    boolean isSafeToUpdate = jsonObject.get("isSafeToUpdate").getAsBoolean();
    String name = jsonObject.get("name").getAsString();
    List<FlutterWidgetProperty> children = jsonObject.get("children") == null ? null : FlutterWidgetProperty.fromJsonArray(jsonObject.get("children").getAsJsonArray());
    FlutterWidgetPropertyEditor editor = jsonObject.get("editor") == null ? null : FlutterWidgetPropertyEditor.fromJson(jsonObject.get("editor").getAsJsonObject());
    FlutterWidgetPropertyValue value = jsonObject.get("value") == null ? null : FlutterWidgetPropertyValue.fromJson(jsonObject.get("value").getAsJsonObject());
    return new FlutterWidgetProperty(documentation, expression, id, isRequired, isSafeToUpdate, name, children, editor, value);
  }

  public static List<FlutterWidgetProperty> fromJsonArray(JsonArray jsonArray) {
    if (jsonArray == null) {
      return EMPTY_LIST;
    }
    List<FlutterWidgetProperty> list = new ArrayList<>(jsonArray.size());
    for (final JsonElement element : jsonArray) {
      list.add(fromJson(element.getAsJsonObject()));
    }
    return list;
  }

  /**
   * The list of children properties, if any. For example any property of type
   * <code>EdgeInsets</code> will have four children properties of type <code>double</code> - left /
   * top / right / bottom.
   */
  public List<FlutterWidgetProperty> getChildren() {
    return children;
  }

  /**
   * The documentation of the property to show to the user. Omitted if the server does not know the
   * documentation, e.g. because the corresponding field is not documented.
   */
  public String getDocumentation() {
    return documentation;
  }

  /**
   * The editor that should be used by the client. This field is omitted if the server does not know
   * the editor for this property, for example because it does not have one of the supported types.
   */
  public FlutterWidgetPropertyEditor getEditor() {
    return editor;
  }

  /**
   * If the value of this property is set, the Dart code of the expression of this property.
   */
  public String getExpression() {
    return expression;
  }

  /**
   * The unique identifier of the property, must be passed back to the server when updating the
   * property value. Identifiers become invalid on any source code change.
   */
  public int getId() {
    return id;
  }

  /**
   * True if the property is required, e.g. because it corresponds to a required parameter of a
   * constructor.
   */
  public boolean isRequired() {
    return isRequired;
  }

  /**
   * If the property expression is a concrete value (e.g. a literal, or an enum constant), then it is
   * safe to replace the expression with another concrete value. In this case this field is true.
   * Otherwise, for example when the expression is a reference to a field, so that its value is
   * provided from outside, this field is false.
   */
  public boolean isSafeToUpdate() {
    return isSafeToUpdate;
  }

  /**
   * The name of the property to display to the user.
   */
  public String getName() {
    return name;
  }

  /**
   * If the expression is set, and the server knows the value of the expression, this field is set.
   */
  public FlutterWidgetPropertyValue getValue() {
    return value;
  }

  @Override
  public int hashCode() {
    return Objects.hash(
      documentation,
      expression,
      id,
      isRequired,
      isSafeToUpdate,
      name,
      children,
      editor,
      value
    );
  }

  public JsonObject toJson() {
    JsonObject jsonObject = new JsonObject();
    if (documentation != null) {
      jsonObject.addProperty("documentation", documentation);
    }
    if (expression != null) {
      jsonObject.addProperty("expression", expression);
    }
    jsonObject.addProperty("id", id);
    jsonObject.addProperty("isRequired", isRequired);
    jsonObject.addProperty("isSafeToUpdate", isSafeToUpdate);
    jsonObject.addProperty("name", name);
    if (children != null) {
      JsonArray jsonArrayChildren = new JsonArray();
      for (FlutterWidgetProperty elt : children) {
        jsonArrayChildren.add(elt.toJson());
      }
      jsonObject.add("children", jsonArrayChildren);
    }
    if (editor != null) {
      jsonObject.add("editor", editor.toJson());
    }
    if (value != null) {
      jsonObject.add("value", value.toJson());
    }
    return jsonObject;
  }

  @Override
  public String toString() {
    StringBuilder builder = new StringBuilder();
    builder.append("[");
    builder.append("documentation=");
    builder.append(documentation);
    builder.append(", ");
    builder.append("expression=");
    builder.append(expression);
    builder.append(", ");
    builder.append("id=");
    builder.append(id);
    builder.append(", ");
    builder.append("isRequired=");
    builder.append(isRequired);
    builder.append(", ");
    builder.append("isSafeToUpdate=");
    builder.append(isSafeToUpdate);
    builder.append(", ");
    builder.append("name=");
    builder.append(name);
    builder.append(", ");
    builder.append("children=");
    builder.append(children == null ? "null" : children.stream().map(String::valueOf).collect(Collectors.joining(", ")));
    builder.append(", ");
    builder.append("editor=");
    builder.append(editor);
    builder.append(", ");
    builder.append("value=");
    builder.append(value);
    builder.append("]");
    return builder.toString();
  }

}
