WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 4 THEN '1-4' 
      ELSE '5-7' 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.dischtime IS NOT NULL
),
acs_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
      WHEN d.seq_num = 1 AND (
        (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111')) OR
        (d.icd_version = 10 AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      ) THEN 1 
      ELSE 0 
    END) AS has_primary_acs,
    MAX(CASE 
      WHEN d.seq_num > 1 AND (
        (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '4111')) OR
        (d.icd_version = 10 AND (d.icd_code = 'I200' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      ) THEN 1 
      ELSE 0 
    END) AS has_secondary_acs
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id
),
filtered_cohort AS (
  SELECT 
    c.*,
    f.has_primary_acs,
    f.has_secondary_acs,
    CASE 
      WHEN f.has_primary_acs = 1 THEN 'Primary'
      WHEN f.has_secondary_acs = 1 THEN 'Secondary'
    END AS diagnosis_type
  FROM cohort c
  INNER JOIN acs_flags f 
    ON c.hadm_id = f.hadm_id
  WHERE (f.has_primary_acs = 1 OR f.has_secondary_acs = 1)
    AND c.los_days BETWEEN 1 AND 7
    AND CASE 
      WHEN f.has_primary_acs = 1 THEN 'Primary'
      WHEN f.has_secondary_acs = 1 THEN 'Secondary'
    END IS NOT NULL
),
ultrasounds AS (
  SELECT 
    fc.hadm_id,
    COUNT(CASE 
      WHEN LOWER(dip.long_title) LIKE '%echocardiography%' THEN 1 
    END) AS ultrasound_count
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
    ON fc.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  GROUP BY fc.hadm_id
)
SELECT 
  fc.diagnosis_type,
  fc.los_group,
  COUNT(*) AS num_admissions,
  AVG(u.ultrasound_count) AS mean_ultrasounds,
  MIN(u.ultrasound_count) AS min_ultrasounds,
  MAX(u.ultrasound_count) AS max_ultrasounds
FROM filtered_cohort fc
INNER JOIN ultrasounds u 
  ON fc.hadm_id = u.hadm_id
GROUP BY fc.diagnosis_type, fc.los_group
ORDER BY fc.diagnosis_type, fc.los_group;