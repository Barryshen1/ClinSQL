WITH IschemicStrokeAdmissions AS (
  SELECT DISTINCT
    a.hadm_id,
    -- Calculate hospital LOS in fractional days for higher precision
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.hadm_id = diag.hadm_id
  WHERE
    -- 1. Filter for female patients aged 50-60
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    -- 2. Filter for primary diagnosis
    AND diag.seq_num = 1
    -- 3. Filter for ICD codes corresponding to ischemic stroke
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '434%') -- ICD-9 for Occlusion of cerebral arteries
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%') -- ICD-10 for Cerebral infarction
    )
)
-- Final step: Calculate the 25th percentile of the LOS for the cohort
SELECT
  APPROX_QUANTILES(hospital_los_days, 100)[OFFSET(25)] AS p25_hospital_los_days
FROM
  IschemicStrokeAdmissions
WHERE
  hospital_los_days IS NOT NULL; -- Ensure we only consider admissions with a valid LOS;