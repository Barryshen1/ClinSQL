WITH ugib_adms AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      -- ICD-9 codes for primary UGIB (examples: esophageal hemorrhage, hematemesis, bleeding ulcers)
      (di.icd_version = 9 
       AND di.icd_code IN ('5307', '53101', '53121', '53141', '53161', '53201', '53221', '53241', '53261', 
                           '53301', '53321', '53341', '53361', '53401', '53421', '53441', '53461', '5780'))
      OR
      -- ICD-10 codes for primary UGIB (examples: esophageal/gastric/duodenal/peptic ulcers with hemorrhage)
      (di.icd_version = 10 
       AND di.icd_code IN ('K226', 'K250', 'K252', 'K254', 'K256', 'K260', 'K262', 'K264', 'K266', 
                           'K270', 'K272', 'K274', 'K276', 'K280', 'K282', 'K284', 'K286'))
    )
),
los_data AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN ugib_adms ua
    ON a.subject_id = ua.subject_id AND a.hadm_id = ua.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.dischtime > a.admittime  -- Ensure valid LOS
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr_days
FROM los_data;