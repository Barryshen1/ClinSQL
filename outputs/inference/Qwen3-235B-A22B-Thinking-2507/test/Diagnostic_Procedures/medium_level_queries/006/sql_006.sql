WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      GROUP BY hadm_id
      HAVING 
        SUM(CASE WHEN icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520' THEN 1 ELSE 0 END) > 0
        AND SUM(CASE WHEN icd_code LIKE 'R57%' OR icd_code = 'R6521' THEN 1 ELSE 0 END) = 0
    )
),
base_admissions_enhanced AS (
  SELECT 
    b.hadm_id,
    DATETIME_DIFF(b.dischtime, b.admittime, DAY) AS hospital_los,
    CASE WHEN COUNT(i.stay_id) > 0 THEN 1 ELSE 0 END AS has_icu
  FROM base_admissions b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON b.hadm_id = i.hadm_id
  GROUP BY b.hadm_id, b.dischtime, b.admittime
),
ultrasound_counts AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title ILIKE '%ultrasound%'
  GROUP BY p.hadm_id
),
final_data AS (
  SELECT 
    e.hadm_id,
    e.hospital_los,
    e.has_icu,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM base_admissions_enhanced e
  LEFT JOIN ultrasound_counts u
    ON e.hadm_id = u.hadm_id
  WHERE e.hospital_los BETWEEN 1 AND 8
)
SELECT 
  has_icu,
  CASE 
    WHEN hospital_los BETWEEN 1 AND 4 THEN '1-4'
    WHEN hospital_los BETWEEN 5 AND 8 THEN '5-8'
  END AS los_group,
  COUNT(*) AS patient_count,
  AVG(ultrasound_count) AS mean_ultrasounds
FROM final_data
GROUP BY has_icu, los_group
ORDER BY has_icu, los_group;