WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

ultrasound_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ultra%' OR LOWER(label) LIKE '%echo%'
),

ultrasound_counts AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pe.itemid) AS ultrasound_count
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.hadm_id = pe.hadm_id
  INNER JOIN
    ultrasound_items ui
    ON pe.itemid = ui.itemid
  GROUP BY
    c.hadm_id
),

admission_ultrasound AS (
  SELECT
    c.los_group,
    c.icu_flag,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM
    cohort c
  LEFT JOIN
    ultrasound_counts u
    ON c.hadm_id = u.hadm_id
)

SELECT
  los_group,
  icu_flag,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75
FROM
  admission_ultrasound
GROUP BY
  los_group,
  icu_flag
ORDER BY
  los_group,
  icu_flag;