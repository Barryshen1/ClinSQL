WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
    AND diag.seq_num = 1   -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddiag
    ON diag.icd_code = ddiag.icd_code
    AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'M'
    AND adm.insurance = 'Medicare'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND adm.admission_location LIKE 'EMERGENCY DEPARTMENT%'
    AND LOWER(ddiag.long_title) LIKE '%transient ischemic attack%'
),
readmit_flag AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    idx.los_days,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS next
        WHERE next.subject_id = idx.subject_id
          AND next.admittime > idx.dischtime
          AND DATETIME_DIFF(next.admittime, idx.dischtime, DAY) <= 30
      )
      THEN 1 ELSE 0
    END AS readmitted
  FROM cohort AS idx
),
stats AS (
  SELECT
    COUNT(*) AS total_index_stays,
    SUM(readmitted) AS n_readmitted,
    SAFE_DIVIDE(SUM(readmitted), COUNT(*)) AS readmission_rate,
    APPROX_QUANTILES(CASE WHEN readmitted=1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(CASE WHEN readmitted=0 THEN los_days END, 100)[OFFSET(50)] AS median_los_nonreadmitted,
    SAFE_DIVIDE(SUM(CASE WHEN los_days > 10 THEN 1 ELSE 0 END), COUNT(*)) AS pct_los_over_10_days
  FROM readmit_flag
)
SELECT
  readmission_rate,
  median_los_readmitted,
  median_los_nonreadmitted,
  pct_los_over_10_days
FROM stats;