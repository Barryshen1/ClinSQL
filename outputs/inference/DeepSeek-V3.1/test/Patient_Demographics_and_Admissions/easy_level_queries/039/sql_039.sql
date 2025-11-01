WITH first_icu_stays AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.los,
    ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
pneumonia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE dd.icd_code LIKE 'J18%'
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM first_icu_stays ie
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ie.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON ie.hadm_id = a.hadm_id
INNER JOIN pneumonia_admissions pa
  ON ie.hadm_id = pa.hadm_id
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND ie.stay_seq = 1;