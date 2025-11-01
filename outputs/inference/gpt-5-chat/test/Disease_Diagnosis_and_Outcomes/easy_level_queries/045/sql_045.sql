WITH hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),
copd_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%' 
     OR LOWER(dd.long_title) LIKE '%copd%'
)
SELECT
  STDDEV_SAMP(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 77 AND 87
  AND a.hadm_id IN (SELECT hadm_id FROM hf_hadm)
  AND a.hadm_id IN (SELECT hadm_id FROM copd_hadm);