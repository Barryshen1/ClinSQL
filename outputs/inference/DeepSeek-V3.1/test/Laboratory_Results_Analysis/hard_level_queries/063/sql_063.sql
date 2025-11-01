WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Calculate age at admission: anchor_age is age at anchor_year, so we adjust by anchor_year and year of admission
    -- But since anchor_age is fixed and admission year varies, we approximate by using anchor_age directly.
    -- The cohort is 53-63, so we rely on anchor_age.
    pt.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 53 AND 63
    AND dx.icd_code LIKE 'I26%'
    AND dx.icd_version = 10
),

labs_72hr AS (
  SELECT 
    lab.subject_id, 
    lab.hadm_id,
    lab.itemid,
    lab.flag
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN cohort c
    ON lab.hadm_id = c.hadm_id
  WHERE lab.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND lab.charttime >= c.admittime
    AND lab.flag IS NOT NULL
    AND lab.flag IN ('High', 'Low')
),

instability_scores AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_days,
    COUNT(DISTINCT l.itemid) AS instability_score
  FROM cohort c
  LEFT JOIN labs_72hr l
    ON c.hadm_id = l.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.los_days
),

percentile_calc AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM instability_scores
)

SELECT 
  -- For patients with score >= 75th percentile
  (SELECT COUNT(*) FROM instability_scores WHERE instability_score >= (SELECT p75_score FROM percentile_calc)) AS high_score_count,
  (SELECT COUNT(*) FROM instability_scores WHERE instability_score >= (SELECT p75_score FROM percentile_calc) AND hospital_expire_flag = 1) AS high_score_deaths,
  ROUND((SELECT COUNT(*) FROM instability_scores WHERE instability_score >= (SELECT p75_score FROM percentile_calc) AND hospital_expire_flag = 1) * 100.0 / 
        (SELECT COUNT(*) FROM instability_scores WHERE instability_score >= (SELECT p75_score FROM percentile_calc)), 2) AS mortality_percent,
  ROUND(AVG(CASE WHEN instability_score >= (SELECT p75_score FROM percentile_calc) THEN los_days END), 2) AS mean_los_days,
  -- Compare critical-lab rates: average instability score for high group vs low group
  ROUND(AVG(CASE WHEN instability_score >= (SELECT p75_score FROM percentile_calc) THEN instability_score END), 2) AS avg_score_high,
  ROUND(AVG(CASE WHEN instability_score < (SELECT p75_score FROM percentile_calc) THEN instability_score END), 2) AS avg_score_low
FROM instability_scores;