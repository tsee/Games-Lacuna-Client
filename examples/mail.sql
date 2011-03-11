BEGIN;

CREATE TABLE mail_index (
  id INTEGER PRIMARY KEY NOT NULL,
  subject VARCHAR(255) NOT NULL,
  date_sent DATETIME NOT NULL,
  from_name VARCHAR(255) NOT NULL,
  from_id INTEGER(11) NOT NULL,
  to_name VARCHAR(255) NOT NULL,
  to_id INTEGER(11) NOT NULL,
  has_read BOOLEAN NOT NULL,
  has_replied BOOLEAN NOT NULL,
  has_archived BOOLEAN NOT NULL DEFAULT '0',
  body_preview TEXT NOT NULL,
  tags_json TEXT NOT NULL
);

CREATE TABLE mail_message (
  id INTEGER PRIMARY KEY NOT NULL,
  recipients_json TEXT NOT NULL,
  body TEXT NOT NULL,
  image_url TEXT,
  image_title TEXT,
  image_link TEXT,
  link_url TEXT,
  link_label TEXT,
  table_json TEXT,
  map_surface VARCHAR(255),
  map_buildings_json TEXT
);


COMMIT;

