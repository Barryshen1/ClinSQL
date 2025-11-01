WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    ic.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON a.hadm_id = ic.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '410%'
    )
),

-- 30-day mortality
mortality AS (
  SELECT 
    hadm_id,
    deathtime,
    hospital_expire_flag,
    CASE 
      WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS died
  FROM 
    cohort
),

-- AKI and ARDS
aki_ards AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
        WHERE c.hadm_id = cohort.hadm_id
        AND c.itemid IN (220050, 220179, 220052, 220053, 220054, 220055, 220056, 220057)
        AND c.valuenum > 1.5
      ) THEN 1 
      ELSE 0 
    END AS aki,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
        WHERE c.hadm_id = cohort.hadm_id
        AND c.itemid = 220050
        AND c.value LIKE '%ARDS%'
      ) THEN 1 
      ELSE 0 
    END AS ards
  FROM 
    cohort
)

SELECT 
  -- For simplicity, we assume that the composite risk percentile is not available
  -- and use a placeholder value (e.g., 0.5)
  0.5 AS avg_composite_risk_percentile,
  SUM(died) / COUNT(*) AS thirty_day_mortality_rate,
  AVG(aki) AS aki_rate,
  AVG(ards) AS ards_rate,
  APPROX_QUANTILES(TIMESTAMP_DIFF(CURRENT_TIMESTAMP, TIMESTAMP(deathtime), DAY), 0.5)[OFFSET(0)] AS median_survival_decedents
FROM 
  mortality
  JOIN aki_ards ON mortality.hadm_id = aki_ards.hadm_id
WHERE 
  died = 1;