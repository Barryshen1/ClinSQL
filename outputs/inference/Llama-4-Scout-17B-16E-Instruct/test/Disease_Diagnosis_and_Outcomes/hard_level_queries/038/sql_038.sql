WITH 
-- Define AKI cohort
aki_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.labevents`
      WHERE 
        itemid = 220050
        AND valuenum > 1.5  -- Example AKI criteria
    )
),

-- Calculate 30-day mortality
mortality AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS died,
    dischtime,
    deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculate SOFA score components
sofa_components AS (
  SELECT 
    subject_id,
    hadm_id,
    itemid,
    valuenum,
    charttime
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (220050, 220179, 220052, 220053, 220054, 220055)  -- Example itemids for SOFA score
),

-- Calculate median SOFA score
sofa_score AS (
  SELECT 
    hadm_id,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_sofa_score,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS sofa_score_q1,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS sofa_score_q3
  FROM 
    sofa_components
),

-- General male inpatients aged 74–84
general_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
)

-- Final query
SELECT 
  COUNT(DISTINCT ac.hadm_id) AS aki_patients,
  APPROX_QUANTILES(ss.median_sofa_score, 100)[OFFSET(50)] AS median_sofa_score,
  APPROX_QUANTILES(ss.median_sofa_score, 100)[OFFSET(25)] AS sofa_score_q1,
  APPROX_QUANTILES(ss.median_sofa_score, 100)[OFFSET(75)] AS sofa_score_q3,
  SUM(m.died) / COUNT(DISTINCT ac.hadm_id) AS thirty_day_mortality,
  AVG(ac.dischtime - ac.admittime) AS survivor_los
FROM 
  aki_cohort ac
JOIN 
  mortality m ON ac.hadm_id = m.hadm_id
JOIN 
  sofa_score ss ON ac.hadm_id = ss.hadm_id
WHERE 
  m.died = 0  -- Survivors
;

-- For comparison with general male inpatients
SELECT 
  COUNT(DISTINCT gc.hadm_id) AS general_patients,
  SUM(m.died) / COUNT(DISTINCT gc.hadm_id) AS thirty_day_mortality_general,
  AVG(gc.dischtime - gc.admittime) AS survivor_los_general
FROM 
  general_cohort gc
JOIN 
  mortality m ON gc.hadm_id = m.hadm_id
WHERE 
  m.died = 0  -- Survivors
;