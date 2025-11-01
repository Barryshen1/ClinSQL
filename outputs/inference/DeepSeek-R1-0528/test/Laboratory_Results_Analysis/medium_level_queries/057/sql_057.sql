WITH acs_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age BETWEEN 79 AND 89
    AND (
      (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code = '4111'))
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I20.0%' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I23%' OR diag.icd_code LIKE 'I24.8%' OR diag.icd_code LIKE 'I24.9%'))
    )
),
first_troponin AS (
  SELECT
    lab.hadm_id,
    lab.valuenum AS troponin_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN
    acs_admissions adm
    ON lab.hadm_id = adm.hadm_id
    AND lab.subject_id = adm.subject_id
  WHERE
    lab.itemid = 51003  -- Troponin T
    AND lab.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY lab.hadm_id ORDER BY lab.charttime) = 1
)
SELECT
  CASE
    WHEN troponin_value <= 0.04 THEN 'normal'
    WHEN troponin_value > 0.04 AND troponin_value <= 0.1 THEN 'borderline'
    WHEN troponin_value > 0.1 THEN 'elevated'
  END AS category,
  COUNT(hadm_id) AS admission_count
FROM
  first_troponin
GROUP BY
  category;