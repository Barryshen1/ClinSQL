WITH sepsis_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
male_sepsis_adm AS (
  SELECT DISTINCT s.hadm_id, a.subject_id, DATE(a.dischtime) AS discharge_date
  FROM sepsis_hadm s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
)
SELECT 
  APPROX_QUANTILES(le.valuenum, 5)[OFFSET(3)] AS p75_platelet_count
FROM male_sepsis_adm m
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON le.hadm_id = m.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
WHERE DATE(le.charttime) = m.discharge_date
  AND LOWER(dli.label) LIKE '%platelet%'
  AND le.valuenum IS NOT NULL;