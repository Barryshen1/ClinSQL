WITH cohort AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
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
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1
    AND (
      -- ICD-9 codes for primary upper GI bleed (e.g., ulcers with hemorrhage, varices, esophagitis/gastritis)
      (d.icd_version = 9 AND d.icd_code IN (
        '4560', '4562', '5307', '53081', 
        '53101', '53111', '53121', '53141', '53151', '53161',
        '53201', '53211', '53221', '53241', '53251', '53261',
        '53301', '53311', '53321', '53341', '53351', '53361',
        '53401', '53411', '53421', '53441', '53451', '53461',
        '53501', '53511', '53521', '53541', '53551', '53561',
        '53783', '5780'
      ))
      OR
      -- ICD-10 codes for primary upper GI bleed (e.g., ulcers with hemorrhage, varices)
      (d.icd_version = 10 AND d.icd_code IN (
        'I8501', 'I8511', 'I8521', 'I8531', 
        'K226', 'K250', 'K251', 'K252', 'K254', 'K255', 'K256',
        'K260', 'K261', 'K262', 'K264', 'K265', 'K266',
        'K270', 'K271', 'K272', 'K274', 'K275', 'K276',
        'K280', 'K281', 'K282', 'K284', 'K285', 'K286'
      ))
    )
)
SELECT 
  PERCENTILE_CONT(los_days, 0.25) AS p25_los_days
FROM cohort
WHERE 
  age_at_admit BETWEEN 74 AND 84
  AND los_days >= 0;  -- Exclude any anomalous negative LOS (rare);