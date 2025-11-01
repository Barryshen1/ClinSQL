WITH ugib_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(long_title, r'(?i)upper gastrointestinal bleeding') OR
    -- Include common ICD codes for UGIB if needed for precision
    icd_code IN ('K250','K252','K254','K256','5307','53021','5310','5312','5314','5316','5320')
),
copd_exac_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(long_title, r'(?i)copd with exacerbation') OR
    icd_code IN ('J441','49121')
)
SELECT 
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
WHERE 
  p.anchor_age BETWEEN 86 AND 96
  AND p.gender = 'M'
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN ugib_codes uc
      ON di.icd_code = uc.icd_code AND di.icd_version = uc.icd_version
    WHERE di.subject_id = p.subject_id AND di.hadm_id = a.hadm_id
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN copd_exac_codes cc
      ON di.icd_code = cc.icd_code AND di.icd_version = cc.icd_version
    WHERE di.subject_id = p.subject_id AND di.hadm_id = a.hadm_id
  );