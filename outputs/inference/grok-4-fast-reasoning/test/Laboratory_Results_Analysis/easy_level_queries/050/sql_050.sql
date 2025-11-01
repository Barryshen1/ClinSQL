WITH sepsis_adms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did 
    ON di.icd_code = did.icd_code 
    AND di.icd_version = did.icd_version
  WHERE LOWER(did.long_title) LIKE '%sepsis%'
),
male_sepsis_adms AS (
  SELECT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN sepsis_adms s 
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
),
adm_platelets AS (
  SELECT 
    msa.hadm_id, 
    msa.admittime, 
    le.charttime, 
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY msa.hadm_id ORDER BY le.charttime) AS rn
  FROM male_sepsis_adms msa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON msa.subject_id = le.subject_id 
    AND le.hadm_id = msa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
    ON le.itemid = dli.itemid
  WHERE le.charttime >= msa.admittime
    AND LOWER(dli.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
)
SELECT STDDEV(valuenum) AS admission_platelet_stddev
FROM adm_platelets
WHERE rn = 1;