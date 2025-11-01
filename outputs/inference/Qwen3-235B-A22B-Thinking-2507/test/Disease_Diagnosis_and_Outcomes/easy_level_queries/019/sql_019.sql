WITH admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),
sepsis_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    a.gender = 'F'
    AND a.age_at_adm BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND (
      d.icd_code LIKE 'A40%' 
      OR d.icd_code LIKE 'A41%' 
      OR d.icd_code = 'R6520' 
      OR d.icd_code = 'R6521'
    )
)
SELECT 
  STDDEV(los_days) AS std_los
FROM (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM sepsis_admissions
);