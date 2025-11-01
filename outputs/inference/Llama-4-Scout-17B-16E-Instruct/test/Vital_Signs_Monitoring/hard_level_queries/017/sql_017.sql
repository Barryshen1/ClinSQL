WITH 
-- Identify population of interest
population AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id
      AND d.icd_code LIKE '%493%'
    )
),

-- Assume instability score is derived from chartevents
instability_score AS (
  SELECT 
    subject_id,
    stay_id,
    charttime,
    -- Simplified example: assume itemid = 220050 is the instability score
    valuenum AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid = 220050  -- This itemid is an example; actual itemid may vary
)

-- Calculate statistics
SELECT 
  STDDEV(`instability_score`) AS sd,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY `instability_score`) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY `instability_score`) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY `instability_score`) AS p75,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY `instability_score`) AS p95,
  AVG(ic.los) AS avg_icu_los,
  SUM(CASE WHEN p.dod IS NOT NULL THEN 1 ELSE 0 END) / COUNT(p.subject_id) AS mortality_rate
FROM 
  population p
JOIN 
  icustays ic ON p.subject_id = ic.subject_id AND p.stay_id = ic.stay_id
JOIN 
  instability_score is_score 
    ON p.subject_id = is_score.subject_id AND p.stay_id = is_score.stay_id
    AND is_score.charttime BETWEEN p.intime AND TIMESTAMP_ADD(p.intime, INTERVAL 72 HOUR);