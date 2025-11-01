WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND LOWER(a.admission_type) LIKE '%emergency%'
    AND a.edregtime IS NOT NULL
    AND d.seq_num = 1
    AND d.icd_code LIKE 'I63%'
),
base2 AS (
  SELECT *
  FROM base
),
readmission AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.index_los_days,
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmit_flag
  FROM base2 AS b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON a2.subject_id = b.subject_id
   AND a2.admittime > b.dischtime
   AND a2.admittime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY)
  GROUP BY b.subject_id, b.hadm_id, b.admittime, b.dischtime, b.index_los_days
),
readmit_labeled AS (
  SELECT *,
         CASE WHEN readmit_flag = 1 THEN 'Readmitted within 30 days'
              ELSE 'No readmission within 30 days' END AS readmit_group
  FROM readmission
),
median_calcs AS (
  SELECT readmit_group, APPROX_QUANTILES(index_los_days, 100) AS quantiles
  FROM readmit_labeled
  GROUP BY readmit_group
),
pct_gt5 AS (
  SELECT 100.0 * SUM(CASE WHEN index_los_days > 5 THEN 1 ELSE 0 END) / COUNT(*) AS pct_gt5
  FROM readmit_labeled
)
SELECT
  -- 30-day readmission rate
  (SELECT AVG(readmit_flag) FROM readmission) AS readmission_rate_30d,
  -- Median index LOS for readmitted within 30 days
  (SELECT quantiles[OFFSET(49)]
     FROM median_calcs
     WHERE readmit_group = 'Readmitted within 30 days') AS median_index_los_days_readmitted,
  -- Median index LOS for no readmission within 30 days
  (SELECT quantiles[OFFSET(49)]
     FROM median_calcs
     WHERE readmit_group = 'No readmission within 30 days') AS median_index_los_days_no_readmission,
  -- Percent index stays > 5 days
  (SELECT pct_gt5 FROM pct_gt5) AS pct_index_stays_gt5_days;