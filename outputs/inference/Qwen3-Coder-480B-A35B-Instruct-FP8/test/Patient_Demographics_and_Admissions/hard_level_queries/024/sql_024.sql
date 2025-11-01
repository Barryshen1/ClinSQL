WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.insurance = 'Medicare'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 76 AND 86
),

stroke_admits AS (
  SELECT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND dd.icd_code LIKE '434%')
      OR
      (d.icd_version = 10 AND dd.icd_code LIKE 'I63%')
    )
),

index_admits AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
      stroke_admits
  )
  WHERE
    rn = 1
),

readmit_flags AS (
  SELECT
    ia.*,
    CASE
      WHEN readmit.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    index_admits ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` readmit
  ON
    ia.subject_id = readmit.subject_id
    AND readmit.admittime > ia.dischtime
    AND DATETIME_DIFF(readmit.admittime, ia.dischtime, DAY) <= 30
    AND readmit.hadm_id != ia.hadm_id
),

readmit_stats AS (
  SELECT
    readmitted_30d,
    los_days,
    CASE WHEN los_days > 5 THEN 1 ELSE 0 END AS los_gt_5
  FROM
    readmit_flags
)

SELECT
  ROUND(AVG(readmitted_30d), 4) AS readmission_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(AVG(los_gt_5), 4) AS pct_los_gt_5_days
FROM
  readmit_stats

UNION ALL

SELECT
  NULL AS readmission_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(AVG(los_gt_5), 4) AS pct_los_gt_5_days
FROM
  readmit_stats
WHERE
  readmitted_30d = 1

UNION ALL

SELECT
  NULL AS readmission_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(AVG(los_gt_5), 4) AS pct_los_gt_5_days
FROM
  readmit_stats
WHERE
  readmitted_30d = 0;