WITH
-- Define age range and gender filter
male_81_91 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- Get admissions with pulmonary embolism (ICD-10 I26.*)
pe_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I26.%'
    AND a.subject_id IN (SELECT subject_id FROM male_81_91)
),

-- Calculate comorbidity score (count of distinct ICD codes)
comorbidity_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_81_91)
  GROUP BY
    a.subject_id, a.hadm_id
),

-- Calculate 75th percentile of comorbidity scores
percentile_75 AS (
  SELECT
    PERCENTILE_CONT(comorbidity_score, 0.75) OVER() AS p75_score
  FROM
    comorbidity_scores
  LIMIT 1
),

-- Filter for high comorbidity patients (score > 75th percentile)
high_comorbidity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.comorbidity_score,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    m.dod
  FROM
    comorbidity_scores c
  JOIN
    pe_admissions p ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  JOIN
    male_81_91 m ON c.subject_id = m.subject_id
  CROSS JOIN
    percentile_75
  WHERE
    c.comorbidity_score > p75_score
),

-- Calculate 90-day mortality
mortality_90day AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.comorbidity_score,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    CASE
      WHEN h.hospital_expire_flag = 1 THEN 1
      WHEN h.dod IS NOT NULL AND
           TIMESTAMP_DIFF(h.dod, h.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_within_90days
  FROM
    high_comorbidity h
),

-- Calculate AKI/ARDS rates
aki_ards_rates AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.died_within_90days,
    MAX(CASE WHEN d.icd_code LIKE 'N17.%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN d.icd_code LIKE 'J80.%' THEN 1 ELSE 0 END) AS has_ards
  FROM
    mortality_90day m
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON m.subject_id = d.subject_id AND m.hadm_id = d.hadm_id
  GROUP BY
    m.subject_id, m.hadm_id, m.died_within_90days
),

-- Calculate length of stay (LOS)
los_calc AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_81_91)
),

-- Calculate risk percentiles
risk_percentiles AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.comorbidity_score,
    PERCENT_RANK() OVER (ORDER BY m.comorbidity_score) AS risk_percentile
  FROM
    mortality_90day m
),

-- Final results
final_results AS (
  SELECT
    -- Mean risk score
    AVG(m.comorbidity_score) AS mean_risk_score,

    -- 90-day mortality rate
    AVG(m.died_within_90days) AS mortality_90day_rate,

    -- AKI/ARDS rates among survivors vs all
    AVG(CASE WHEN a.died_within_90days = 0 THEN a.has_aki ELSE NULL END) AS aki_rate_survivors,
    AVG(a.has_aki) AS aki_rate_all,

    AVG(CASE WHEN a.died_within_90days = 0 THEN a.has_ards ELSE NULL END) AS ards_rate_survivors,
    AVG(a.has_ards) AS ards_rate_all,

    -- LOS comparison
    AVG(CASE WHEN m.died_within_90days = 0 THEN l.los_days ELSE NULL END) AS avg_los_survivors,
    AVG(l.los_days) AS avg_los_all,

    -- Matched-profile risk percentile (average of all percentiles)
    AVG(r.risk_percentile) AS avg_risk_percentile
  FROM
    mortality_90day m
  JOIN
    aki_ards_rates a ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
  JOIN
    los_calc l ON m.subject_id = l.subject_id AND m.hadm_id = l.hadm_id
  JOIN
    risk_percentiles r ON m.subject_id = r.subject_id AND m.hadm_id = r.hadm_id
)

SELECT * FROM final_results;