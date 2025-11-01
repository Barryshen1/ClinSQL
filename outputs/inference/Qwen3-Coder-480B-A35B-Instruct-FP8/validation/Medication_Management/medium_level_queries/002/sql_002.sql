WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

glp1_administrations AS (
  SELECT
    e.hadm_id,
    e.charttime,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    eligible_admissions a
  ON
    e.hadm_id = a.hadm_id
  WHERE
    REGEXP_CONTAINS(LOWER(e.medication), r'(semaglutide|liraglutide|dulaglutide|exenatide)')
    AND e.charttime BETWEEN a.admittime AND a.dischtime
),

first_48h_use AS (
  SELECT
    hadm_id
  FROM
    glp1_administrations
  WHERE
    charttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 48 HOUR)
  GROUP BY
    hadm_id
),

last_12h_use AS (
  SELECT
    hadm_id
  FROM
    glp1_administrations
  WHERE
    charttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime
  GROUP BY
    hadm_id
),

admission_counts AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    eligible_admissions
),

first_48h_stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS count_first_48h
  FROM
    first_48h_use
),

last_12h_stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS count_last_12h
  FROM
    last_12h_use
)

SELECT
  ROUND((first_48h.count_first_48h / total.total_admissions) * 100, 2) AS prevalence_first_48h_pct,
  ROUND((last_12h.count_last_12h / total.total_admissions) * 100, 2) AS prevalence_last_12h_pct,
  ROUND(
    ABS(
      (first_48h.count_first_48h / total.total_admissions) * 100
      - (last_12h.count_last_12h / total.total_admissions) * 100
    ),
    2
  ) AS abs_diff_pct
FROM
  admission_counts total,
  first_48h_stats first_48h,
  last_12h_stats last_12h;