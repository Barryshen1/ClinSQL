WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code IN (
        '578.0', '578.1', '578.9', 
        '531.0', '531.2', '531.4', '531.6',
        '532.0', '532.2', '532.4', '532.6',
        '533.0', '533.2', '533.4', '533.6',
        '534.0', '534.2', '534.4', '534.6'
      ))
      OR 
      (d.icd_version = 10 AND d.icd_code IN (
        'K25.0', 'K25.2', 'K25.4', 'K25.6',
        'K26.0', 'K26.2', 'K26.4', 'K26.6',
        'K27.0', 'K27.2', 'K27.4', 'K27.6',
        'K28.0', 'K28.2', 'K28.4', 'K28.6',
        'K92.0', 'K92.1', 'K92.2'
      ))
    )
    AND a.dischtime > a.admittime  -- Valid LOS
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  cohort
WHERE 
  age_at_admission BETWEEN 77 AND 87;