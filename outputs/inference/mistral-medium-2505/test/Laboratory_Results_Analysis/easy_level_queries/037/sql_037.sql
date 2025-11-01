WITH
-- Get male patients aged around 43
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 40 AND 45
),

-- Get admissions with sepsis diagnosis
sepsis_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients)
    AND (
      -- ICD-9 codes for sepsis
      (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
      OR
      -- ICD-10 codes for sepsis
      (d.icd_version = 10 AND d.icd_code LIKE 'R65%' OR d.icd_code LIKE 'A41%')
    )
),

-- Get peak platelet count for each patient
peak_platelets AS (
  SELECT
    l.subject_id,
    MAX(l.valuenum) AS max_platelet_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    l.subject_id IN (SELECT subject_id FROM sepsis_admissions)
    AND dl.label = 'Platelets'
    AND l.valuenum IS NOT NULL
  GROUP BY
    l.subject_id
)

-- Calculate the 75th percentile of peak platelet counts
SELECT
  PERCENTILE_CONT(max_platelet_count, 0.75) OVER() AS percentile_75_platelet_count
FROM
  peak_platelets
LIMIT 1;