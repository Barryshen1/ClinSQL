WITH copd_patients AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON diag.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE d_icd.long_title LIKE '%Chronic obstructive pulmonary disease%' 
    AND pat.gender = 'F' 
    AND pat.anchor_age = 50
),
sodium_measurements AS (
  SELECT lab.hadm_id, lab.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON lab.itemid = d_lab.itemid
  WHERE d_lab.label = 'Sodium' AND lab.valuenum IS NOT NULL
),
nadir_sodium AS (
  SELECT sm.hadm_id, MIN(sm.valuenum) AS nadir_sodium
  FROM sodium_measurements sm
  WHERE sm.hadm_id IN (SELECT hadm_id FROM copd_patients)
  GROUP BY sm.hadm_id
)
SELECT STDDEV(nadir_sodium.nadir_sodium) AS std_dev_nadir_sodium
FROM nadir_sodium;