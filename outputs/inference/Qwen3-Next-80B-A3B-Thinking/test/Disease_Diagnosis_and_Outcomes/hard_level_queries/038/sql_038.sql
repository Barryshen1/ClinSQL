WITH male_74_84 AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag, 
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 74 AND 84
),
diagnoses AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
creatinine AS (
  SELECT 
    subject_id, 
    hadm_id, 
    charttime, 
    valuenum AS creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 50912
),
baseline_creatinine AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    MIN(c.creatinine) AS baseline
  FROM creatinine c
  JOIN male_74_84 m 
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  WHERE c.charttime <= m.admittime
  GROUP BY c.subject_id, c.hadm_id
),
max_creatinine AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    MAX(c.creatinine) AS max_creatinine
  FROM creatinine c
  JOIN male_74_84 m 
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  WHERE c.charttime >= m.admittime
  GROUP BY c.subject_id, c.hadm_id
),
aki_stage AS (
  SELECT 
    b.subject_id, 
    b.hadm_id,
    CASE 
      WHEN m.max_creatinine >= 3 * b.baseline OR m.max_creatinine >= 4.0 THEN 3
      WHEN m.max_creatinine >= 2 * b.baseline THEN 2
      WHEN m.max_creatinine >= b.baseline + 0.3 OR m.max_creatinine >= 1.5 * b.baseline THEN 1
      ELSE 0
    END AS aki_stage
  FROM baseline_creatinine b
  JOIN max_creatinine m 
    ON b.subject_id = m.subject_id AND b.hadm_id = m.hadm_id
),
cohort AS (
  SELECT 
    m.*,
    d.has_aki,
    d.has_ards,
    a.aki_stage,
    CASE 
      WHEN m.dod IS NOT NULL AND m.dod <= m.dischtime + INTERVAL '30' DAY 
      THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    CASE 
      WHEN m.hospital_expire_flag = 0 
      THEN DATE_DIFF(m.dischtime, m.admittime, 'DAY') 
      ELSE NULL 
    END AS los_survivor
  FROM male_74_84 m
  LEFT JOIN diagnoses d ON m.hadm_id = d.hadm_id
  LEFT JOIN aki_stage a ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
),
aki_cohort AS (
  SELECT * FROM cohort WHERE has_aki = 1
),
general_cohort AS (
  SELECT * FROM cohort
),
aki_metrics AS (
  SELECT 
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY aki_stage) AS median_risk_score,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY aki_stage) AS q1_risk_score,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY aki_stage) AS q3_risk_score,
    AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
    AVG(has_ards) AS ards_rate,
    AVG(los_survivor) AS avg_los_survivor
  FROM aki_cohort
),
general_metrics AS (
  SELECT 
    AVG(has_ards) AS ards_rate,
    AVG(los_survivor) AS avg_los_survivor
  FROM general_cohort
)
SELECT 
  a.median_risk_score,
  CONCAT(ROUND(a.q1_risk_score, 2), '-', ROUND(a.q3_risk_score, 2)) AS iqr_risk_score,
  ROUND(a.thirty_day_mortality_rate, 4) AS thirty_day_mortality_rate,
  ROUND(a.ards_rate, 4) AS aki_ards_rate,
  ROUND(g.ards_rate, 4) AS general_ards_rate,
  ROUND(a.avg_los_survivor, 2) AS aki_avg_los_survivor,
  ROUND(g.avg_los_survivor, 2) AS general_avg_los_survivor
FROM aki_metrics a, general_metrics g;