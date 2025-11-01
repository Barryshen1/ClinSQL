WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Sepsis%' OR dicd.long_title LIKE '%septic%'
),
male_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
),
male_sepsis_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN male_patients mp ON a.subject_id = mp.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
),
platelet_counts AS (
  SELECT l.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Platelet Count' AND l.hadm_id IN (SELECT hadm_id FROM male_sepsis_admissions)
)
SELECT STDDEV(valuenum) as platelet_stddev
FROM platelet_counts
WHERE rn = 1;