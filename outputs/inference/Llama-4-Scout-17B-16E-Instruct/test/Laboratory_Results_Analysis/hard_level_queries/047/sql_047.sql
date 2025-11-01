WITH 
-- Define ARDS patients and calculate instability score
ards_patients AS (
  SELECT 
    ic.stay_id,
    ic.hadm_id,
    ic.subject_id,
    ic.intime,
    ic.outtime,
    -- Simple instability score example: using heart rate and respiratory rate
    SUM(CASE 
      WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1 
      WHEN ce.itemid = 220179 AND ce.valuenum > 30 THEN 1 
      ELSE 0 
    END) / COUNT(ce.itemid) AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON ic.stay_id = ce.stay_id 
  WHERE 
    ic.intime BETWEEN TIMESTAMP_SUB(ic.intime, INTERVAL 3 DAY) AND ic.intime
    AND ic.subject_id IN (
      SELECT 
        a.subject_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.admissions` a
      JOIN 
        `physionet-data.mimiciv_3_1_hosp.patients` p 
          ON a.subject_id = p.subject_id
      WHERE 
        p.gender = 'M' 
        AND p.anchor_age BETWEEN 71 AND 81
    )
  GROUP BY 
    ic.stay_id, ic.hadm_id, ic.subject_id, ic.intime, ic.outtime
),

-- Calculate 90th percentile instability score
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(90)] AS percentile_90
  FROM 
    ards_patients
)

-- Analyze patients above the threshold
SELECT 
  ap.subject_id,
  ap.hadm_id,
  -- Mortality
  CASE 
    WHEN a.deathtime IS NOT NULL THEN 1 
    ELSE 0 
  END AS mortality,
  -- Mean LOS
  TIMESTAMP_DIFF(ic.outtime, ic.intime, DAY) AS los_days,
  -- Critical lab rates
  AVG(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS high_heart_rate,
  AVG(CASE WHEN ce.itemid = 220179 AND ce.valuenum > 30 THEN 1 ELSE 0 END) AS high_respiratory_rate
FROM 
  ards_patients ap
JOIN 
  `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ap.stay_id = ce.stay_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ap.hadm_id = a.hadm_id
JOIN 
  icustays ic 
    ON ap.hadm_id = ic.hadm_id AND ap.stay_id = ic.stay_id
JOIN 
  percentile_score ps 
    ON ap.instability_score >= ps.percentile_90
GROUP BY 
  ap.subject_id, ap.hadm_id, a.deathtime, ic.intime, ic.outtime;