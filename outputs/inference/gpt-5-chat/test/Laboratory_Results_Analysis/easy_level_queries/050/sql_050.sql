WITH sepsis_male_44 AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 44
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
platelet_events AS (
  SELECT sepsis.subject_id, sepsis.hadm_id, MIN(le.charttime) AS first_charttime
  FROM sepsis_male_44 AS sepsis
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON sepsis.subject_id = le.subject_id
   AND sepsis.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
  GROUP BY sepsis.subject_id, sepsis.hadm_id
),
platelet_values AS (
  SELECT pe.subject_id, pe.hadm_id, le.valuenum
  FROM platelet_events AS pe
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pe.subject_id = le.subject_id
   AND pe.hadm_id = le.hadm_id
   AND pe.first_charttime = le.charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
)
SELECT STDDEV(valuenum) AS admission_platelet_stddev
FROM platelet_values;