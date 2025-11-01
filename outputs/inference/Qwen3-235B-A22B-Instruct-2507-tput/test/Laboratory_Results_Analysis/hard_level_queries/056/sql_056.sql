WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
asthma_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%asthma%'
    OR di.icd_code IN ('J45', 'J450', 'J451', 'J458', 'J459', 'J46')
),
cohort AS (
  SELECT pa.*
  FROM patient_admissions pa
  JOIN asthma_diagnoses ad ON pa.hadm_id = ad.hadm_id
  WHERE pa.age_at_admit >= 55 AND pa.age_at_admit <= 65
),
lab_abnormalities AS (
  SELECT
    l.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  JOIN cohort c ON l.hadm_id = c.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY l.hadm_id
),
percentile_95 AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 1000)[OFFSET(950)] AS p95
  FROM lab_abnormalities
),
grouped_cohort AS (
  SELECT
    c.*,
    COALESCE(la.abnormal_lab_count, 0) AS abnormal_lab_count,
    CASE
      WHEN la.abnormal_lab_count >= p.p95 THEN 'top_5_percentile'
      ELSE 'general'
    END AS group_label
  FROM cohort c
  LEFT JOIN lab_abnormalities la ON c.hadm_id = la.hadm_id
  CROSS JOIN percentile_95 p
)
SELECT
  group_label,
  AVG(EXTRACT(DAY FROM (dischtime - admittime)) + 
      EXTRACT(HOUR FROM (dischtime - admittime))/24.0) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(abnormal_lab_count) AS avg_abnormal_lab_count
FROM grouped_cohort
GROUP BY group_label
ORDER BY group_label;