WITH eligible_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age >= 90
    AND anchor_age <= 100
),
sepsis_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN eligible_patients ep
    ON di.subject_id = ep.subject_id
  WHERE (
    -- ICD-9 codes for sepsis/septicemia/SIRS
    (di.icd_version = 9 AND (
      di.icd_code IN ('995.91', '995.92', '785.52') OR
      di.icd_code LIKE '038.%'
    ))
    OR
    -- ICD-10 codes for sepsis
    (di.icd_version = 10 AND (
      di.icd_code LIKE 'A40%' OR
      di.icd_code LIKE 'A41%' OR
      di.icd_code LIKE 'R65.2%' OR
      di.icd_code LIKE 'T81.4%'
    ))
  )
)
SELECT STDDEV(los) AS stddev_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN sepsis_admissions sa
  ON i.subject_id = sa.subject_id
  AND i.hadm_id = sa.hadm_id;