WITH principal_stroke AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 9 AND (
          di.icd_code LIKE '430%' OR
          di.icd_code LIKE '431%' OR
          di.icd_code LIKE '432%'))
      OR
      (di.icd_version = 10 AND (
          di.icd_code LIKE 'I60%' OR
          di.icd_code LIKE 'I61%' OR
          di.icd_code LIKE 'I62%'))
    )
),
index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN principal_stroke ps
    ON a.subject_id = ps.subject_id AND a.hadm_id = ps.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND (
      LOWER(a.admission_location) LIKE '%emergency%' OR a.edregtime IS NOT NULL
    )
),
readmission_flags AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    idx.los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = idx.subject_id
        AND a2.admittime > idx.dischtime
        AND a2.admittime <= DATETIME_ADD(idx.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_flag
  FROM index_admissions idx
),
summary AS (
  SELECT
    readmit_flag,
    COUNT(*) AS n_admissions,
    COUNTIF(readmit_flag=1) / COUNT(*) OVER() AS readmission_rate_overall, -- overall rate
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    100.0 * COUNTIF(los_days > 4) / COUNT(*) AS pct_los_gt4
  FROM readmission_flags
  GROUP BY readmit_flag
)
SELECT * FROM summary
ORDER BY readmit_flag DESC;