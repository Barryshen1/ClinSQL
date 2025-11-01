WITH 
cohort AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 74 AND 84
),
upper_gi_bleed AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE d.seq_num = 1  
  AND (
    (d.icd_version = 9 AND d.icd_code IN ('530.7', '531.0', '531.1', '531.2', '531.3', '531.4', '532.0', '532.1', '532.2', '532.3', '532.4', '533.0', '533.1', '533.2', '533.3', '533.4', '534.0', '534.1', '534.2', '534.3', '534.4', '578.0', '578.1', '578.9'))
    OR 
    (d.icd_version = 10 AND dicd.icd_code IN ('K22.6', 'K25.0', 'K25.4', 'K26.0', 'K26.4', 'K27.0', 'K27.4', 'K28.0', 'K28.4', 'K92.0', 'K92.1', 'K92.2'))
  )
)
SELECT 
  APPROX_QUANTILES(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24, 100)[OFFSET(25)] AS percentile_25th_los
FROM cohort c
INNER JOIN upper_gi_bleed ugb ON c.hadm_id = ugb.hadm_id;