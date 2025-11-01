WITH hemorrhagic_stroke AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 9 AND (
            d.icd_code LIKE '430%' OR
            d.icd_code LIKE '431%' OR
            d.icd_code LIKE '432%'))
     OR (d.icd_version = 10 AND (
            d.icd_code LIKE 'I60%' OR
            d.icd_code LIKE 'I61%' OR
            d.icd_code LIKE 'I62%'))
),
copd_exacerbation AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 9 AND d.icd_code = '49121')
     OR (d.icd_version = 10 AND d.icd_code = 'J441')
),
cohort AS (
  SELECT a.subject_id, a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.hadm_id IN (SELECT hadm_id FROM hemorrhagic_stroke)
    AND a.hadm_id IN (SELECT hadm_id FROM copd_exacerbation)
)
SELECT
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(2)] AS median,
  quantiles[OFFSET(3)] AS q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(los, 4) AS quantiles
  FROM cohort
);