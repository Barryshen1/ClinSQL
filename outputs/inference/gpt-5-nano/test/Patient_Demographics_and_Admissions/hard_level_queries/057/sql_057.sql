WITH index_candidates AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND UPPER(a.admission_type) = 'EMERGENCY'
    AND a.insurance LIKE '%Medicare%'
    AND di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%urinary tract infection%'
),
index_admissions AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.admittime,
    ic.dischtime,
    ic.index_los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` r
      WHERE r.subject_id = ic.subject_id
        AND r.hadm_id <> ic.hadm_id
        AND r.admittime > ic.dischtime
        AND TIMESTAMP_DIFF(r.admittime, ic.dischtime, DAY) <= 30
    ) THEN 1 ELSE 0 END AS readmit_30
  FROM index_candidates ic
),
per_group AS (
  SELECT
    CAST(readmit_30 AS INT64) AS readmit_flag,
    COUNT(*) AS n_index_admissions,
    APPROX_QUANTILES(index_los_days, 2)[OFFSET(1)] AS median_index_los_days,
    100.0 * SUM(CASE WHEN index_los_days > 9.0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt_9_days
  FROM index_admissions
  GROUP BY readmit_30
  ORDER BY readmit_30
),
overall_rate AS (
  SELECT 100.0 * SUM(readmit_30) / COUNT(*) AS readmission_rate_30d
  FROM index_admissions
)
SELECT
  g.readmit_flag AS readmit_flag,
  g.n_index_admissions,
  g.median_index_los_days,
  g.pct_los_gt_9_days,
  o.readmission_rate_30d
FROM per_group AS g
CROSS JOIN overall_rate AS o
ORDER BY g.readmit_flag;