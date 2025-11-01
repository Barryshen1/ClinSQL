WITH sepsis_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Check for any ICU stay for this admission
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'no ICU' END AS icu_status,
    -- Count ultrasounds for this admission
    COUNT(proc.icd_code) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  -- Pre-aggregate ICU stays to avoid duplicate rows
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON adm.hadm_id = icu.hadm_id
  -- Left join to count ultrasounds
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
    AND proc.icd_code IN (
        -- ICD-10 PCS Ultrasound codes
        '3E033', '3E043', '3E053', '3E063', '3E073', '3E083', '3E093', '3E0A3',
        '3E0B3', '3E0C3', '3E0D3', '3E0F3', '3E0G3', '3E0H3', '3E0J3', '3E0K3',
        -- ICD-10 CM Ultrasound codes
        'B41', 'B42', 'B43', 'B44',
        -- ICD-9 Ultrasound codes
        '88.71', '88.72', '88.73', '88.74', '88.75', '88.76', '88.77', '88.78', '88.79'
    )
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
    AND diag.icd_code IN ('A41.9', 'R65.10') -- Sepsis without shock
    AND diag.icd_version = 10
  GROUP BY
    adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, icu_status
),
los_groups AS (
  SELECT
    subject_id,
    hadm_id,
    icu_status,
    ultrasound_count,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE 'Other'
    END AS los_group
  FROM sepsis_cohort
  WHERE los_days BETWEEN 1 AND 8
)
SELECT
  icu_status,
  los_group,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM los_groups
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;