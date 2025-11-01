WITH primary_dka_hhs AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%ketoacidosis%' 
      OR LOWER(dd.long_title) LIKE '%hyperosmolar%' 
      OR LOWER(dd.long_title) LIKE '%hyperglycemic state%'
    )
)
SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_hospital_los_days
FROM (
  SELECT 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN primary_dka_hhs pdkh 
    ON a.hadm_id = pdkh.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
);