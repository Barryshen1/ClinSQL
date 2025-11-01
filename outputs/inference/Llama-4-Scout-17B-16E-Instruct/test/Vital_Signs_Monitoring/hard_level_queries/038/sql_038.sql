WITH 
-- Identify status epilepticus patients and filter by age and gender
se_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id 
      AND d.icd_code LIKE '345.3%'  -- Status epilepticus ICD code
    )
),

-- Calculate vital-instability index (example: heart rate and MAP)
vital_instability AS (
  SELECT 
    subject_id,
    stay_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (220050, 220179)  -- Example itemids for heart rate and blood pressure
    AND charttime BETWEEN intime AND outtime
),

-- Calculate percentiles and mean of vital-instability index
vital_stats AS (
  SELECT 
    subject_id,
    stay_id,
    APPROX_QUANTILES(valuenum, 4) AS quantiles,
    AVG(valuenum) OVER (PARTITION BY subject_id, stay_id) AS mean
  FROM 
    vital_instability
  GROUP BY 
    subject_id, stay_id
),

-- Unpack quantiles
vital_stats_unpacked AS (
  SELECT 
    subject_id,
    stay_id,
    quantiles[OFFSET(1)] AS p25,
    quantiles[OFFSET(2)] AS p50,
    quantiles[OFFSET(3)] AS p75,
    quantiles[OFFSET(4)] AS p90,
    mean
  FROM 
    vital_stats
),

-- Calculate outcomes for comparison
outcomes AS (
  SELECT 
    subject_id,
    stay_id,
    intime,
    outtime,
    TIMESTAMPDIFF(HOUR, intime, outtime) AS icu_los,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = subject_id 
        AND d.icd_code LIKE '345.3%'  
      ) THEN 'SE Group'
      ELSE 'General ICU'
    END AS group_name
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Calculate tachycardia and MAP < 65 burden
burden AS (
  SELECT 
    subject_id,
    stay_id,
    SUM(CASE WHEN valuenum > 100 THEN 1 ELSE 0 END) / COUNT(*) AS tachycardia_burden,
    SUM(CASE WHEN valuenum < 65 THEN 1 ELSE 0 END) / COUNT(*) AS map_lt_65_burden
  FROM 
    vital_instability
  GROUP BY 
    subject_id, stay_id
)

-- Final query to compare outcomes
SELECT 
  o.group_name,
  COUNT(DISTINCT o.subject_id) AS n,
  AVG(o.icu_los) AS mean_icu_los,
  COALESCE(b.tachycardia_burden, 0) AS tachycardia_burden,
  COALESCE(b.map_lt_65_burden, 0) AS map_lt_65_burden,
  vs.p25 AS vital_instability_p25,
  vs.p50 AS vital_instability_p50,
  vs.p75 AS vital_instability_p75,
  vs.p90 AS vital_instability_p90,
  vs.mean AS vital_instability_mean
FROM 
  outcomes o
  LEFT JOIN vital_stats_unpacked vs 
    ON o.subject_id = vs.subject_id AND o.stay_id = vs.stay_id
  LEFT JOIN burden b 
    ON o.subject_id = b.subject_id AND o.stay_id = b.stay_id
GROUP BY 
  o.group_name,
  vs.p25,
  vs.p50,
  vs.p75,
  vs.p90,
  vs.mean,
  b.tachycardia_burden,
  b.map_lt_65_burden;