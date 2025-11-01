WITH stroke_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  -- Only primary diagnosis
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND (
      -- Hemorrhagic stroke ICD-9 codes
      (d.icd_version = 9 AND (
        d.icd_code LIKE '430%' OR
        d.icd_code LIKE '431%' OR
        d.icd_code LIKE '432%'
      ))
      OR
      -- Hemorrhagic stroke ICD-10 codes
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I60%' OR
        d.icd_code LIKE 'I61%' OR
        d.icd_code LIKE 'I62%'
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS los_75th_percentile_days
FROM
  stroke_patients;