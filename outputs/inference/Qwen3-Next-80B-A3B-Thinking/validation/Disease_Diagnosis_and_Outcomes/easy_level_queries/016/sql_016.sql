WITH filtered_admissions AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE 
        d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%pneumonia%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE 
        d.hadm_id = a.hadm_id
        AND (LOWER(di.long_title) LIKE '%copd%' OR LOWER(di.long_title) LIKE '%chronic obstructive pulmonary disease%')
    )
)
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS percentile_75
FROM (
  SELECT 
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los
  FROM filtered_admissions
)
LIMIT 1;