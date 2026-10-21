#include "ruby.h"

static VALUE mMH;
static VALUE mVan;
static VALUE mNative;

static VALUE k_key;
static VALUE k_thickness;
static VALUE k_thickness_value;
static VALUE k_code;
static VALUE k_default_code;
static VALUE k_count;
static VALUE k_two_face;
static VALUE k_visible;
static VALUE k_all_hidden;
static VALUE k_color;
static VALUE k_ids;
static VALUE k_ancestor_ids;
static VALUE k_paths;
static VALUE k_id;
static VALUE k_path;

static VALUE hash_get(VALUE hash, VALUE key) {
  return rb_hash_aref(hash, key);
}

static void hash_set(VALUE hash, VALUE key, VALUE value) {
  rb_hash_aset(hash, key, value);
}

static VALUE new_row_from_item(VALUE item, VALUE key) {
  VALUE row = rb_hash_new();
  hash_set(row, k_key, key);
  hash_set(row, k_thickness, hash_get(item, k_thickness));
  hash_set(row, k_thickness_value, hash_get(item, k_thickness_value));
  hash_set(row, k_code, hash_get(item, k_code));
  hash_set(row, k_default_code, hash_get(item, k_default_code));
  hash_set(row, k_count, INT2NUM(0));
  hash_set(row, k_two_face, INT2NUM(0));
  hash_set(row, k_visible, Qfalse);
  hash_set(row, k_all_hidden, Qtrue);
  hash_set(row, k_color, hash_get(item, k_color));
  hash_set(row, k_ids, rb_ary_new());
  hash_set(row, k_ancestor_ids, rb_ary_new());
  hash_set(row, k_paths, rb_ary_new());
  return row;
}

static void append_array(VALUE target, VALUE values) {
  long i;
  values = rb_Array(values);
  for (i = 0; i < RARRAY_LEN(values); ++i) {
    rb_ary_push(target, rb_ary_entry(values, i));
  }
}

static int uniq_row_arrays(VALUE key, VALUE row, VALUE ignored) {
  VALUE ids = hash_get(row, k_ids);
  VALUE ancestor_ids = hash_get(row, k_ancestor_ids);
  if (!NIL_P(ids)) {
    hash_set(row, k_ids, rb_funcall(ids, rb_intern("uniq"), 0));
  }
  if (!NIL_P(ancestor_ids)) {
    hash_set(row, k_ancestor_ids, rb_funcall(ancestor_ids, rb_intern("uniq"), 0));
  }
  return ST_CONTINUE;
}

static VALUE native_group_items(VALUE self, VALUE items) {
  long i;
  VALUE buckets = rb_hash_new();
  items = rb_Array(items);

  for (i = 0; i < RARRAY_LEN(items); ++i) {
    VALUE item = rb_ary_entry(items, i);
    VALUE key = hash_get(item, k_key);
    VALUE row;
    VALUE count;
    VALUE visible;

    if (NIL_P(key)) {
      continue;
    }

    row = rb_hash_aref(buckets, key);
    if (NIL_P(row)) {
      row = new_row_from_item(item, key);
      rb_hash_aset(buckets, key, row);
    }

    count = hash_get(row, k_count);
    hash_set(row, k_count, INT2NUM(NUM2INT(count) + 1));

    visible = hash_get(item, k_visible);
    if (RTEST(visible)) {
      hash_set(row, k_visible, Qtrue);
      hash_set(row, k_all_hidden, Qfalse);
    }

    rb_ary_push(hash_get(row, k_ids), hash_get(item, k_id));
    append_array(hash_get(row, k_ancestor_ids), hash_get(item, k_ancestor_ids));
    rb_ary_push(hash_get(row, k_paths), hash_get(item, k_path));
  }

  rb_hash_foreach(buckets, uniq_row_arrays, Qnil);
  return buckets;
}

static long uf_find(long *parent, long index) {
  long root = index;
  while (parent[root] != root) {
    root = parent[root];
  }
  while (parent[index] != root) {
    long next = parent[index];
    parent[index] = root;
    index = next;
  }
  return root;
}

static void uf_union(long *parent, unsigned char *rank, long left, long right) {
  long root_left = uf_find(parent, left);
  long root_right = uf_find(parent, right);
  if (root_left == root_right) return;

  if (rank[root_left] < rank[root_right]) {
    long swap = root_left;
    root_left = root_right;
    root_right = swap;
  }
  parent[root_right] = root_left;
  if (rank[root_left] == rank[root_right]) rank[root_left]++;
}

static double axis_gap(double min_a, double max_a, double min_b, double max_b) {
  if (min_b > max_a) return min_b - max_a;
  if (min_a > max_b) return min_a - max_b;
  return 0.0;
}

/* Exact AABB distance clustering for the shared MH::Geo::Cluster facade. */
static VALUE native_distance_cluster_indices(VALUE self, VALUE boxes, VALUE threshold_value) {
  long length;
  long count;
  long i;
  long j;
  long *parent;
  unsigned char *rank;
  double threshold;
  double gap_sq;
  VALUE groups;

  boxes = rb_Array(boxes);
  length = RARRAY_LEN(boxes);
  if (length % 6 != 0) {
    rb_raise(rb_eArgError, "boxes_flat length must be divisible by 6");
  }
  count = length / 6;
  if (count == 0) return rb_ary_new();

  threshold = NUM2DBL(threshold_value);
  gap_sq = threshold * threshold;
  parent = ALLOC_N(long, count);
  rank = ALLOC_N(unsigned char, count);
  for (i = 0; i < count; ++i) {
    parent[i] = i;
    rank[i] = 0;
  }

  for (i = 0; i < count; ++i) {
    long offset_a = i * 6;
    double min_ax = NUM2DBL(rb_ary_entry(boxes, offset_a));
    double max_ax = NUM2DBL(rb_ary_entry(boxes, offset_a + 1));
    double min_ay = NUM2DBL(rb_ary_entry(boxes, offset_a + 2));
    double max_ay = NUM2DBL(rb_ary_entry(boxes, offset_a + 3));
    double min_az = NUM2DBL(rb_ary_entry(boxes, offset_a + 4));
    double max_az = NUM2DBL(rb_ary_entry(boxes, offset_a + 5));

    for (j = i + 1; j < count; ++j) {
      long offset_b = j * 6;
      double dx = axis_gap(min_ax, max_ax,
                           NUM2DBL(rb_ary_entry(boxes, offset_b)),
                           NUM2DBL(rb_ary_entry(boxes, offset_b + 1)));
      double dy = axis_gap(min_ay, max_ay,
                           NUM2DBL(rb_ary_entry(boxes, offset_b + 2)),
                           NUM2DBL(rb_ary_entry(boxes, offset_b + 3)));
      double dz = axis_gap(min_az, max_az,
                           NUM2DBL(rb_ary_entry(boxes, offset_b + 4)),
                           NUM2DBL(rb_ary_entry(boxes, offset_b + 5)));
      if (dx * dx + dy * dy + dz * dz < gap_sq) {
        uf_union(parent, rank, i, j);
      }
    }
  }

  groups = rb_hash_new();
  for (i = 0; i < count; ++i) {
    VALUE key = LONG2NUM(uf_find(parent, i));
    VALUE group = rb_hash_aref(groups, key);
    if (NIL_P(group)) {
      group = rb_ary_new();
      rb_hash_aset(groups, key, group);
    }
    rb_ary_push(group, LONG2NUM(i));
  }

  xfree(parent);
  xfree(rank);
  return rb_funcall(groups, rb_intern("values"), 0);
}

void Init_mh_van_native(void) {
  mMH = rb_define_module("MH");
  mVan = rb_define_module_under(mMH, "Van");
  mNative = rb_define_module_under(mVan, "Native");

  k_key = rb_str_new_cstr("key");
  k_thickness = rb_str_new_cstr("thickness");
  k_thickness_value = rb_str_new_cstr("thickness_value");
  k_code = rb_str_new_cstr("code");
  k_default_code = rb_str_new_cstr("default_code");
  k_count = rb_str_new_cstr("count");
  k_two_face = rb_str_new_cstr("two_face");
  k_visible = rb_str_new_cstr("visible");
  k_all_hidden = rb_str_new_cstr("all_hidden");
  k_color = rb_str_new_cstr("color");
  k_ids = rb_str_new_cstr("ids");
  k_ancestor_ids = rb_str_new_cstr("ancestor_ids");
  k_paths = rb_str_new_cstr("paths");
  k_id = rb_str_new_cstr("id");
  k_path = rb_str_new_cstr("path");

  rb_global_variable(&k_key);
  rb_global_variable(&k_thickness);
  rb_global_variable(&k_thickness_value);
  rb_global_variable(&k_code);
  rb_global_variable(&k_default_code);
  rb_global_variable(&k_count);
  rb_global_variable(&k_two_face);
  rb_global_variable(&k_visible);
  rb_global_variable(&k_all_hidden);
  rb_global_variable(&k_color);
  rb_global_variable(&k_ids);
  rb_global_variable(&k_ancestor_ids);
  rb_global_variable(&k_paths);
  rb_global_variable(&k_id);
  rb_global_variable(&k_path);

  rb_define_singleton_method(mNative, "group_items", native_group_items, 1);
  rb_define_singleton_method(mNative, "distance_cluster_indices", native_distance_cluster_indices, 2);
}
