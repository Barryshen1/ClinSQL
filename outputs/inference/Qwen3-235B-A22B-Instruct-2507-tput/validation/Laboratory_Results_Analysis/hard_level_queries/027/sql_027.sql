WITH cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND LOWER(d.long_title) LIKE '%lower gastrointestinal bleed%'
),
first_admission AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN cohort c ON a.subject_id = c.subject_id
  WHERE a.admittime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
lab_72h AS (
  SELECT le.subject_id, le.hadm_id,
         le.valuenum, le.ref_range_lower, le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN first_admission fa
    ON le.hadm_id = fa.hadm_id
  WHERE le.charttime >= fa.admittime
    AND le.charttime <= DATETIME_ADD(fa.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (le.ref_range_lower IS NOT NULL OR le.ref_range_upper IS NOT NULL)
),
abnormal_labs AS (
  SELECT subject_id,
         COUNT(*) AS abnormal_count
  FROM lab_72h
  WHERE (valuenum < ref_range_lower OR valuenum > ref_range_upper)
  GROUP BY subject_id
),
instability_scores AS (
  SELECT fa.subject_id,
         COALESCE(al.abnormal_count, 0) AS instability_score,
         fa.los_days,
         fa.hospital_expire_flag
  FROM first_admission fa
  LEFT JOIN abnormal_labs al ON fa.subject_id = al.subject_id
),
quintiles AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM instability_scores
),
quintile_stats AS (
  SELECT
    quintile,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0.0 END) AS critical_lab_rate,
    COUNT(*) AS patient_count
  FROM quintiles
  GROUP BY quintile
),
cohort_baseline AS (
  SELECT
    AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0.0 END) AS general_inpatient_critical_rate
  FROM instability_scores
)
SELECT
  qs.quintile,
  qs.avg_los,
  qs.mortality_rate,
  qs.critical_lab_rate,
  cb.general_inpatient_critical_rate
FROM quintile_stats qs
CROSS JOIN cohort_baseline cb
ORDER BY qs.quintile;