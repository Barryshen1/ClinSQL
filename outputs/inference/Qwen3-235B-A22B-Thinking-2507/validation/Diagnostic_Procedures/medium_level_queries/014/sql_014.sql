WITH patients_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 83 AND 93
    AND a.dischtime IS NOT NULL
),

admissions_with_acs AS (
  SELECT 
    pc.hadm_id,
    pc.los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = pc.hadm_id 
          AND d.seq_num = 1
          AND ( 
            (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
            OR 
            (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%'))
          )
      ) THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_position
  FROM patients_cohort pc
  WHERE pc.los_days BETWEEN 1 AND 7
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = pc.hadm_id 
        AND ( 
          (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
          OR 
          (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%'))
        )
    )
),

ultrasound_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%ultrasound%'
  GROUP BY h.hadm_id
)

SELECT 
  CASE 
    WHEN ac.los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN ac.los_days BETWEEN 5 AND 7 THEN '5-7'
  END AS stay_group,
  ac.diagnosis_position,
  AVG(COALESCE(uc.ultrasound_count, 0)) AS mean_ultrasound,
  MIN(COALESCE(uc.ultrasound_count, 0)) AS min_ultrasound,
  MAX(COALESCE(uc.ultrasound_count, 0)) AS max_ultrasound
FROM admissions_with_acs ac
LEFT JOIN ultrasound_counts uc 
  ON ac.hadm_id = uc.hadm_id
GROUP BY 
  CASE 
    WHEN ac.los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN ac.los_days BETWEEN 5 AND 7 THEN '5-7'
  END,
  ac.diagnosis_position;