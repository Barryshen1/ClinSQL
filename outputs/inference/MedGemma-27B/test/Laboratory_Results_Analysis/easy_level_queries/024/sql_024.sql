WITH sepsis_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'A41.9' -- Sepsis code
    AND a.admission_type = 'EMERGENCY'
), platelet_counts AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS platelet_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Platelet count'
    AND l.hadm_id IN (
      SELECT
        hadm_id
      FROM sepsis_admissions
    )
    AND l.valuenum IS NOT NULL
)
SELECT
  STDDEV(platelet_count) AS std_dev_platelet_count
FROM platelet_counts;