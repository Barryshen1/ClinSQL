WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pt.gender = 'F'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND adm.admission_type IN ('EMERGENCY', 'URGENT')  -- Community-acquired
    AND (  -- Pneumonia ICD codes
      (diag.icd_version = 9 AND diag.icd_code LIKE '48%')  -- ICD-9: 480.x-488.x
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J1%') -- ICD-10: J12.x-J18.x
    )
    AND (  -- Age 83-93 at admission
      pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)
    ) BETWEEN 83 AND 93
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM cohort;