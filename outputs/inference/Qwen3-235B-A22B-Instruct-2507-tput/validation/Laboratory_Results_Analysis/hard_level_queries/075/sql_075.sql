WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 42 AND 52
    AND a.hadm_id IN (
      SELECT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE LOWER(d.long_title) LIKE '%deep vein thrombosis%'
    )
),

lab_abnormalities AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime 
    AND l.charttime <= c.admittime + INTERVAL '72' HOUR
    AND l.valuenum IS NOT NULL
    AND (
      (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
      OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
    )
  GROUP BY c.hadm_id
),

cohort_with_score AS (
  SELECT 
    c.*,
    COALESCE(l.abnormal_lab_count, 0) AS lab_instability_score
  FROM cohort c
  LEFT JOIN lab_abnormalities l ON c.hadm_id = l.hadm_id
),

percentiles AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95_score
  FROM cohort_with_score
),

high_risk AS (
  SELECT 
    c.*,
    p.p95_score
  FROM cohort_with_score c
  CROSS JOIN percentiles p
  WHERE c.lab_instability_score >= p.p95_score
),

summary_stats AS (
  SELECT
    h.p95_score,
    AVG(CAST(h.hospital_expire_flag AS FLOAT64)) AS mortality_rate_high_risk,
    AVG(TIMESTAMP_DIFF(h.dischtime, h.admittime, HOUR) / 24.0) AS mean_los_high_risk,
    AVG(h.lab_instability_score) AS mean_abnormal_labs_high_risk
  FROM high_risk h
  GROUP BY h.p95_score
),

overall_stats AS (
  SELECT
    AVG(lab_instability_score) AS mean_abnormal_labs_overall
  FROM cohort_with_score
)

SELECT
  s.p95_score,
  s.mortality_rate_high_risk,
  s.mean_los_high_risk,
  s.mean_abnormal_labs_high_risk,
  o.mean_abnormal_labs_overall
FROM summary_stats s
CROSS JOIN overall_stats o;