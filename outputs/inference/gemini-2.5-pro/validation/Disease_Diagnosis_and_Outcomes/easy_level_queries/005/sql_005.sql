WITH cohort AS (
  SELECT DISTINCT -- Ensures each unique admission is counted only once
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.hadm_id = diag.hadm_id
  WHERE
    -- Filter for female patients
    p.gender = 'F'
    -- Filter for patients aged 59-69 at the time of admission
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
    -- Filter for the primary diagnosis
    AND diag.seq_num = 1
    -- Filter for ICD codes corresponding to ischemic stroke
    AND (
      (diag.icd_version = 9 AND (
          diag.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391') -- Occlusion of precerebral arteries with cerebral infarction
          OR STARTS_WITH(diag.icd_code, '434') -- Occlusion of cerebral arteries
      ))
      OR
      (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'I63')) -- Cerebral infarction
    )
)
-- Calculate the median LOS from the filtered cohort
SELECT
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_hospital_los_days
FROM
  cohort;