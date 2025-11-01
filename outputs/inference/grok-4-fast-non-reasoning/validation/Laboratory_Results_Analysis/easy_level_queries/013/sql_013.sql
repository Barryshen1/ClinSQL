WITH copd_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON CAST(d.icd_code AS STRING) = icd.icd_code 
    AND CAST(d.icd_version AS STRING) = icd.icd_version
  WHERE p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '491%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
    )
)
SELECT MAX(le.valuenum) AS max_peak_serum_creatinine_mg_dl
FROM copd_patients cp
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
  ON le.itemid = li.itemid
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON cp.hadm_id = a.hadm_id
WHERE le.itemid IN (50912, 50970)
  AND le.valuenum IS NOT NULL
  AND le.valuenum > 0
  AND (le.valueuom = 'mg/dL' OR le.valueuom IS NULL)
  AND le.charttime >= a.admittime
  AND le.charttime <= a.dischtime
  AND li.label LIKE '%creatinine%';