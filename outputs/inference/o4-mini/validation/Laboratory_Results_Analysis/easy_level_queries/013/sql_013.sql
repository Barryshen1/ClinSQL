WITH female_copd_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON d.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON d.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND d.icd_version = 10
    AND d.icd_code LIKE 'J44%'  -- COPD ICD‐10 codes
),
creatinine_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%creatinin%'
    AND category = 'Chemistry'
)
SELECT
  MAX(le.valuenum) AS max_peak_serum_creatinine_mg_dL
FROM
  `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN creatinine_items AS ci
    ON le.itemid = ci.itemid
  JOIN female_copd_admissions AS fca
    ON le.hadm_id = fca.hadm_id
WHERE
  le.valuenum IS NOT NULL
  AND le.valueuom = 'mg/dL';