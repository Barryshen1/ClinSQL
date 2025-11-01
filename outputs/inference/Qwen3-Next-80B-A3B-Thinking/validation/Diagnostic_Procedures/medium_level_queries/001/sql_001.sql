WITH acs_admissions AS (
  SELECT 
    d.hadm_id,
    CASE 
      WHEN MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      WHEN MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) = 1 THEN 'secondary'
      ELSE NULL
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%acute coronary syndrome%'
    OR di.long_title LIKE '%myocardial infarction%'
    OR di.long_title LIKE '%unstable angina%'
  GROUP BY d.hadm_id
),
patient_info AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
imaging_counts AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE d.label LIKE '%CT%' 
    OR d.label LIKE '%X-ray%' 
    OR d.label LIKE '%radiograph%'
  GROUP BY c.hadm_id
)
SELECT
  CASE 
    WHEN pi.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN pi.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE NULL
  END AS los_category,
  aa.diagnosis_type,
  AVG(COALESCE(ic.imaging_count, 0)) AS mean_imaging,
  MIN(COALESCE(ic.imaging_count, 0)) AS min_imaging,
  MAX(COALESCE(ic.imaging_count, 0)) AS max_imaging
FROM acs_admissions aa
JOIN patient_info pi
  ON aa.hadm_id = pi.hadm_id
LEFT JOIN imaging_counts ic
  ON aa.hadm_id = ic.hadm_id
WHERE pi.gender = 'F'
  AND pi.age_at_admission BETWEEN 77 AND 87
  AND aa.diagnosis_type IS NOT NULL
GROUP BY los_category, diagnosis_type;