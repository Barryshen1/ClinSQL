WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
        AND (icd_code LIKE 'I20%' 
             OR icd_code LIKE 'I21%' 
             OR icd_code LIKE 'I22%' 
             OR icd_code LIKE 'I24%')
    )
),
filtered_admissions AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM base_admissions
  WHERE dischtime IS NOT NULL
    AND DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),
ultrasound_counts AS (
  SELECT 
    fa.hadm_id,
    fa.los_days,
    COUNT(d.icd_code) AS ultrasound_count
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fa.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pi.icd_code = d.icd_code 
    AND pi.icd_version = d.icd_version
    AND (LOWER(d.long_title) LIKE '%ultrasound%' OR LOWER(d.long_title) LIKE '%echo%')
  GROUP BY fa.hadm_id, fa.los_days
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  COUNT(hadm_id) AS admission_count,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM ultrasound_counts
GROUP BY los_group
ORDER BY 
  CASE los_group 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;