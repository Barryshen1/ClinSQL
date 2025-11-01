WITH COPD_Patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND d.icd_code = 'J44.9' -- COPD code
),
Creatinine_Measurements AS (
  SELECT
    c.subject_id,
    c.charttime,
    c.valuenum AS creatinine_value,
    c.valueuom AS creatinine_unit
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON c.itemid = d.itemid
  WHERE
    d.label = 'Creatinine'
    AND c.valueuom = 'mg/dL'
)
SELECT
  MAX(cm.creatinine_value) AS max_peak_creatinine
FROM
  Creatinine_Measurements AS cm
JOIN
  COPD_Patients AS cp
  ON cm.subject_id = cp.subject_id;