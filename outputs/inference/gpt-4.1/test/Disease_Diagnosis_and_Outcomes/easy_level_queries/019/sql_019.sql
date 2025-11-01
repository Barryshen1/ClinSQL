WITH female_aged_67_77 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),
primary_sepsis_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN female_aged_67_77 pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE diag.seq_num = 1
    AND (
      -- ICD-10 sepsis/septic shock
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'A41%' OR
        diag.icd_code LIKE 'R652%'
      ))
      OR
      -- ICD-9 sepsis/septic shock
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '99591' OR
        diag.icd_code LIKE '99592' OR
        diag.icd_code LIKE '038%'
      ))
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  STDDEV_SAMP(
    DATETIME_DIFF(dischtime, admittime, DAY)
  ) AS sd_hospital_los_days
FROM primary_sepsis_admissions
WHERE DATETIME_DIFF(dischtime, admittime, DAY) >= 0;