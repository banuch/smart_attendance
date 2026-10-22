-- Smart Attendance schema (MySQL 8.0+). All times are stored in UTC.

CREATE TABLE shifts (
  id                      CHAR(36)     NOT NULL PRIMARY KEY,
  name                    VARCHAR(100) NOT NULL,
  start_time              CHAR(5)      NOT NULL,            -- HH:mm, local time
  end_time                CHAR(5)      NOT NULL,
  grace_minutes           INT          NOT NULL DEFAULT 10,
  half_day_after_minutes  INT          NOT NULL DEFAULT 120,
  min_full_day_minutes    INT          NOT NULL DEFAULT 360,
  work_days               JSON         NOT NULL,            -- ISO weekdays [1..7]
  created_at              DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sites (
  id             CHAR(36)     NOT NULL PRIMARY KEY,
  name           VARCHAR(100) NOT NULL,
  address        VARCHAR(255) NOT NULL DEFAULT '',
  lat            DOUBLE       NOT NULL,
  lng            DOUBLE       NOT NULL,
  radius_meters  DOUBLE       NOT NULL,
  created_at     DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE users (
  id                CHAR(36)     NOT NULL PRIMARY KEY,
  name              VARCHAR(100) NOT NULL,
  email             VARCHAR(190) NOT NULL,
  password_hash     VARCHAR(100) NOT NULL,
  phone             VARCHAR(30)  NOT NULL DEFAULT '',
  employee_code     VARCHAR(50)  NOT NULL DEFAULT '',
  role              ENUM('admin', 'employee') NOT NULL DEFAULT 'employee',
  active            BOOLEAN      NOT NULL DEFAULT TRUE,
  shift_id          CHAR(36)     NULL,
  device_id         VARCHAR(100) NULL,
  device_model      VARCHAR(100) NULL,
  device_bound_at   DATETIME(3)  NULL,
  face_embedding    JSON         NULL,
  face_path         VARCHAR(255) NULL,
  face_enrolled_at  DATETIME(3)  NULL,
  -- Bumped on password change; invalidates every token issued before.
  token_version     INT          NOT NULL DEFAULT 0,
  created_at        DATETIME(3)  NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
  UNIQUE KEY uq_users_email (email),
  CONSTRAINT fk_users_shift FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sites an employee may punch at. No rows means any site.
CREATE TABLE user_sites (
  user_id  CHAR(36) NOT NULL,
  site_id  CHAR(36) NOT NULL,
  PRIMARY KEY (user_id, site_id),
  CONSTRAINT fk_user_sites_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_user_sites_site FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per employee per day. id = {userId}_{yyyy-MM-dd}.
CREATE TABLE attendance (
  id               VARCHAR(64)  NOT NULL PRIMARY KEY,
  user_id          CHAR(36)     NOT NULL,
  employee_name    VARCHAR(100) NOT NULL,
  date             DATE         NOT NULL,
  shift_id         CHAR(36)     NULL,
  flagged          BOOLEAN      NOT NULL DEFAULT FALSE,
  reviewed         BOOLEAN      NOT NULL DEFAULT FALSE,
  review_decision  ENUM('approved', 'rejected') NULL,
  reviewed_by      CHAR(36)     NULL,
  reviewed_at      DATETIME(3)  NULL,
  review_note      VARCHAR(500) NULL,
  UNIQUE KEY uq_attendance_user_date (user_id, date),
  KEY ix_attendance_date (date),
  KEY ix_attendance_review (flagged, reviewed),
  CONSTRAINT fk_attendance_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Check-in ('in') and check-out ('out'); the primary key makes each write-once.
CREATE TABLE punches (
  attendance_id    VARCHAR(64)  NOT NULL,
  kind             ENUM('in', 'out') NOT NULL,
  time             DATETIME(3)  NOT NULL,                   -- server clock, UTC
  lat              DOUBLE       NOT NULL,
  lng              DOUBLE       NOT NULL,
  accuracy         DOUBLE       NOT NULL,
  site_id          CHAR(36)     NOT NULL,
  site_name        VARCHAR(100) NOT NULL,
  distance_meters  DOUBLE       NOT NULL,
  photo_path       VARCHAR(255) NOT NULL,
  face_score       DOUBLE       NULL,
  flag_reasons     JSON         NOT NULL,
  device_id        VARCHAR(100) NOT NULL,
  PRIMARY KEY (attendance_id, kind),
  CONSTRAINT fk_punches_attendance FOREIGN KEY (attendance_id) REFERENCES attendance (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
