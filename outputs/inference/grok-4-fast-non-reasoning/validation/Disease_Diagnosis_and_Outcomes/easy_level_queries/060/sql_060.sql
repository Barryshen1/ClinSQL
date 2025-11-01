WITH eligible_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.seq_num = 1::INT64  -- primary diagnosis
    AND a.hospital_expire_flag = 0  -- alive at discharge
    AND (
      -- ICD-9 upper GI bleed codes
      (d.icd_version = '9' AND (
        d.icd_code IN ('530.7', '530.71', '530.72', '530.73', '530.74', '530.75', '530.76', '530.77', '530.79',
                       '530.82', '530.84', '530.89',
                       '535.01', '535.41', '535.51', '535.61',
                       '537.83', '578.0')
      ))
      OR
      -- ICD-10 upper GI bleed codes (focused on explicit bleed)
      (d.icd_version = '10' AND (
        d.icd_code IN ('K22.6',  -- Dieulafoy lesion
                       'K25.0', 'K25.1', 'K25.2', 'K25.3', 'K25.4', 'K25.5', 'K25.6',  -- Gastric ulcer bleed/perforation
                       'K26.0', 'K26.1', 'K26.2', 'K26.3', 'K26.4', 'K26.5', 'K26.6',  -- Duodenal ulcer bleed/perforation
                       'K27.0', 'K27.1', 'K27.2', 'K27.3', 'K27.4', 'K27.5', 'K27.6',  -- Peptic ulcer bleed/perforation
                       'K28.0', 'K28.1', 'K28.2', 'K28.3', 'K28.4', 'K28.5', 'K28.6')  -- Gastrojejunal ulcer bleed/perforation
      ))
    )
),
los_data AS (
  SELECT 
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM 
    eligible_admissions
  WHERE 
    DATE_DIFF(dischtime, admittime, DAY) > 0
)
SELECT 
  PERCENTILE_CONT(0.25) OVER() AS p25_los_days
FROM 
  los_data;