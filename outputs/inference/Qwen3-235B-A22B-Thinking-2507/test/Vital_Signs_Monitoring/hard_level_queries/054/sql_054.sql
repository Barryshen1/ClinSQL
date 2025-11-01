WITH icu_stays_with_demographics AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

respiratory_failure_cohort AS (
  SELECT DISTINCT
    s.stay_id,
    s.hadm_id,
    s.intime,
    s.los,
    s.hospital_expire_flag
  FROM icu_stays_with_demographics s
  WHERE s.gender = 'M'
    AND s.age_at_admission BETWEEN 82 AND 92
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = s.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('51881', '51882', '51884', '51885'))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'J960%')
        )
    )
),

burden_calculation AS (
  SELECT
    ce.stay_id,
    SUM(CASE WHEN ce.itemid IN (52, 455, 6701, 220052) AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS burden_map,
    SUM(CASE WHEN ce.itemid IN (211, 220045) AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS burden_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.stay_id = i.stay_id
  WHERE ce.charttime >= i.intime
    AND ce.charttime <= i.intime + INTERVAL '72' HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),

cohort_analysis AS (
  SELECT
    r.stay_id,
    r.los,
    r.hospital_expire_flag,
    COALESCE(b.burden_map, 0) + COALESCE(b.burden_hr, 0) AS composite_burden
  FROM respiratory_failure_cohort r
  LEFT JOIN burden_calculation b
    ON r.stay_id = b.stay_id
),

general_icu_analysis AS (
  SELECT
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    COALESCE(b.burden_map, 0) + COALESCE(b.burden_hr, 0) AS composite_burden
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN burden_calculation b
    ON i.stay_id = b.stay_id
),

specific_stats AS (
  SELECT
    APPROX_QUANTILES(composite_burden, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(composite_burden, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(composite_burden, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(composite_burden, 100)[OFFSET(75)] - 
      APPROX_QUANTILES(composite_burden, 100)[OFFSET(25)] AS iqr,
    AVG(composite_burden) AS avg_burden_specific,
    AVG(los) AS avg_los_specific,
    AVG(hospital_expire_flag) AS mortality_rate_specific
  FROM cohort_analysis
),

general_stats AS (
  SELECT
    AVG(composite_burden) AS avg_burden_general,
    AVG(los) AS avg_los_general,
    AVG(hospital_expire_flag) AS mortality_rate_general
  FROM general_icu_analysis
)

SELECT
  s.p25,
  s.median,
  s.p75,
  s.iqr,
  s.avg_burden_specific,
  s.avg_los_specific,
  s.mortality_rate_specific,
  g.avg_burden_general,
  g.avg_los_general,
  g.mortality_rate_general
FROM specific_stats s
CROSS JOIN general_stats g;