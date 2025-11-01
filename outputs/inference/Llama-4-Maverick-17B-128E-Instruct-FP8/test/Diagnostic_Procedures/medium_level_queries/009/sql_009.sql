WITH cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND dicd.long_title LIKE '%Transient ischemic attack%'
),
admission_info AS (
  SELECT c.subject_id, c.hadm_id,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = c.hadm_id) AS icu_stay
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
),
imaging_counts AS (
  SELECT a.hadm_id, COUNT(*) AS imaging_count
  FROM admission_info a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON a.hadm_id = h.hadm_id
  GROUP BY a.hadm_id
),
final_data AS (
  SELECT ai.los, ai.icu_stay, ic.imaging_count
  FROM admission_info ai
  INNER JOIN imaging_counts ic ON ai.hadm_id = ic.hadm_id
)
SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'outside range'
  END AS los_category,
  icu_stay,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS p75
FROM final_data
GROUP BY los_category, icu_stay
ORDER BY los_category, icu_stay;