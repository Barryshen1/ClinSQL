WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures
  WHERE (
    icd_version = 10 AND icd_code IN ('0210', '0211', '0212', '0213')
  )
  OR (
    icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '3610'
  )
),
first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions
  )
  WHERE rn = 1
),
cabg_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    EXTRACT(YEAR FROM fa.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    fa.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN first_admissions fa ON p.subject_id = fa.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi 
    ON fa.hadm_id = pi.hadm_id AND p.subject_id = pi.subject_id
  INNER JOIN cabg_codes cc 
    ON pi.icd_code = cc.icd_code AND pi.icd_version = cc.icd_version
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM fa.admittime) - p.anchor_year + p.anchor_age BETWEEN 48 AND 58
)
SELECT 
  APPROX_QUANTILES(CAST(hospital_expire_flag AS FLOAT64), 100)[OFFSET(25)] AS mortality_25th_percentile
FROM cabg_patients;