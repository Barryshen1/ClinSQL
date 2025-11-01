WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND (LOWER(a.admission_location) LIKE '%emergency%' OR LOWER(a.admission_location) LIKE '%er%')
    AND di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code IN ('562.11', '562.13', '569.83', '569.2'))
      OR
      (di.icd_version = 10 AND di.icd_code IN ('K55.2', 'K57.1', 'K57.32', 'K57.81', 'K57.91', 'K62.5'))
    )
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
),
index_admissions AS (
  SELECT *
  FROM eligible_admissions
  WHERE admission_seq = 1
),
readmission_flags AS (
  SELECT
    i.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = i.subject_id
          AND a2.admittime > i.dischtime
          AND a2.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_admissions i
)
SELECT
  -- 30-day readmission rate
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_rate_30d,
  -- Median LOS for readmitted vs not
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- Percent with LOS > 6 days, by readmission status
  AVG(CASE WHEN readmitted_30d = 1 THEN CAST(los_days > 6 AS INT64) ELSE NULL END) AS pct_los_gt_6_readmitted,
  AVG(CASE WHEN readmitted_30d = 0 THEN CAST(los_days > 6 AS INT64) ELSE NULL END) AS pct_los_gt_6_not_readmitted
FROM readmission_flags;