WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
mixed_shock AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('78551', '78552')) OR
    (icd_version = 10 AND icd_code IN ('R571', 'R6521'))
  GROUP BY hadm_id
  HAVING 
    COUNT(DISTINCT CASE 
      WHEN (icd_version = 9 AND icd_code = '78551') OR (icd_version = 10 AND icd_code = 'R571') THEN 'cardiogenic'
      WHEN (icd_version = 9 AND icd_code = '78552') OR (icd_version = 10 AND icd_code = 'R6521') THEN 'septic'
    END) = 2
),
filtered_cohort AS (
  SELECT 
    c.* 
  FROM cohort c
  INNER JOIN mixed_shock m
    ON c.hadm_id = m.hadm_id
  WHERE age_at_icu BETWEEN 60 AND 70
),
vitals AS (
  SELECT
    stay_id,
    AVG(CASE WHEN itemid = 220045 THEN valuenum END) AS avg_hr,
    AVG(CASE WHEN itemid IN (220050, 220179) THEN valuenum END) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    stay_id IN (SELECT stay_id FROM filtered_cohort) AND
    itemid IN (220045, 220050, 220179) AND
    valuenum IS NOT NULL AND
    charttime BETWEEN (SELECT MIN(intime) FROM filtered_cohort) AND (SELECT MAX(DATETIME_ADD(intime, INTERVAL 48 HOUR)) FROM filtered_cohort)
  GROUP BY stay_id
  HAVING 
    AVG(CASE WHEN itemid = 220045 THEN valuenum END) IS NOT NULL AND
    AVG(CASE WHEN itemid IN (220050, 220179) THEN valuenum END) IS NOT NULL
),
instability_scores AS (
  SELECT
    fc.*,
    v.avg_hr,
    v.avg_sbp,
    v.avg_hr / v.avg_sbp AS instability_score
  FROM filtered_cohort fc
  INNER JOIN vitals v
    ON fc.stay_id = v.stay_id
),
percentile AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95
  FROM instability_scores
  LIMIT 1
),
top_decile AS (
  SELECT 
    stay_id
  FROM (
    SELECT 
      stay_id,
      instability_score,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS ntile_rank
    FROM instability_scores
  )
  WHERE ntile_rank = 1
),
outcomes AS (
  SELECT
    isc.stay_id,
    -- Hypotension: At least one MAP <65 in first 48h
    MAX(CASE 
      WHEN ce.itemid IN (220052, 220181) AND ce.valuenum < 65 THEN 1 
      ELSE 0 
    END) AS hypotension,
    -- Tachycardia: At least one HR >100 in first 48h
    MAX(CASE 
      WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 
      ELSE 0 
    END) AS tachycardia,
    isc.los AS icu_los,
    MAX(a.hospital_expire_flag) AS mortality
  FROM instability_scores isc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON isc.stay_id = ce.stay_id
    AND ce.charttime BETWEEN isc.intime AND DATETIME_ADD(isc.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220045, 220052, 220181)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON isc.hadm_id = a.hadm_id
  GROUP BY isc.stay_id, isc.los
)
SELECT
  (SELECT p95 FROM percentile) AS cohort_95th_percentile_instability_score,
  'entire_cohort' AS group_name,
  AVG(hypotension) AS hypotension_rate,
  AVG(tachycardia) AS tachycardia_rate,
  AVG(icu_los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM outcomes
UNION ALL
SELECT
  (SELECT p95 FROM percentile) AS cohort_95th_percentile_instability_score,
  'top_decile' AS group_name,
  AVG(hypotension) AS hypotension_rate,
  AVG(tachycardia) AS tachycardia_rate,
  AVG(icu_los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM outcomes
WHERE stay_id IN (SELECT stay_id FROM top_decile);