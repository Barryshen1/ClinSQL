WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hospital_expire_flag = 0
),
pneumonia_admissions AS (
  SELECT 
    ep.*,
    di.seq_num,
    di.icd_code,
    di.icd_version
  FROM 
    eligible_patients ep
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    ep.subject_id = di.subject_id 
    AND ep.hadm_id = di.hadm_id
  WHERE 
    ep.rn = 1
    AND di.seq_num = CAST(1 AS INT64)
    AND di.icd_version = '10'
    AND REGEXP_CONTAINS(di.icd_code, r'^J(12|13|14|15|16|17|18)')
    AND ep.admission_type != 'ELECTIVE'
    AND ep.admission_location NOT LIKE '%HOME%' 
    AND ep.admission_location NOT LIKE '%NURSING%'
),
los_data AS (
  SELECT 
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM 
    pneumonia_admissions
)
SELECT 
  PERCENTILE_CONT(0.25) OVER () AS p25_los_days
FROM 
  los_data
WHERE 
  los_days IS NOT NULL;