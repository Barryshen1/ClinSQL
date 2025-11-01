WITH pneumonia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pneumonia%'
),
copd_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%copd%' 
     OR LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%'
),
eligible_admissions AS (
  SELECT hadm_id
  FROM pneumonia_admissions
  INTERSECT DISTINCT
  SELECT hadm_id
  FROM copd_admissions
)
SELECT
  APPROX_QUANTILES(DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR), 100)[OFFSET(75)] AS los_75th_percentile_hours
FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
  ON ad.subject_id = pa.subject_id
WHERE
  pa.gender = 'M'
  AND pa.anchor_age BETWEEN 68 AND 78
  AND ad.hadm_id IN (SELECT hadm_id FROM eligible_admissions);