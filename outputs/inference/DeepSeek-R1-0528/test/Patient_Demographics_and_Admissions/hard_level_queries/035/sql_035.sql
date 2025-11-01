WITH uti_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'urinary tract infection') OR
    REGEXP_CONTAINS(LOWER(long_title), r'uti')
),
base_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN uti_codes
    ON diag.icd_code = uti_codes.icd_code
    AND diag.icd_version = uti_codes.icd_version
  WHERE
    adm.admission_location = 'TRANSFER FROM SKILLED NURSING FACILITY'
    AND adm.insurance = 'Medicare'
    AND pat.gender = 'M'
    AND diag.seq_num = 1
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 68 AND 78
),
cohort_with_readmission AS (
  SELECT
    base.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm
      WHERE
        readm.subject_id = base.subject_id
        AND readm.hadm_id <> base.hadm_id
        AND readm.admittime > base.dischtime
        AND readm.admittime <= DATETIME_ADD(base.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM base_cohort base
)
SELECT
  '30_day_readmission_rate' AS metric,
  ROUND(AVG(readmitted_30d) * 100, 2) AS value
FROM cohort_with_readmission
UNION ALL
SELECT
  'median_los_readmitted' AS metric,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS value
FROM cohort_with_readmission
WHERE readmitted_30d = 1
UNION ALL
SELECT
  'median_los_non_readmitted' AS metric,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS value
FROM cohort_with_readmission
WHERE readmitted_30d = 0
UNION ALL
SELECT
  'pct_stays_gt_6_days' AS metric,
  ROUND((COUNTIF(los_days > 6) / COUNT(*)) * 100, 2) AS value
FROM cohort_with_readmission;