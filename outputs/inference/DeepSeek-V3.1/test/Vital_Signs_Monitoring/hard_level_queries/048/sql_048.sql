WITH vent_cohort AS (
  SELECT DISTINCT
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ie.stay_id = pe.stay_id
      AND ie.subject_id = pe.subject_id
      AND ie.hadm_id = pe.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
    AND pe.itemid IN (223848, 223849, 224385, 224387)
    AND pe.starttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
),

vitals AS (
  SELECT 
    vc.stay_id,
    MAX(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypotension_event,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_event
  FROM vent_cohort vc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON vc.stay_id = ce.stay_id
      AND vc.subject_id = ce.subject_id
      AND vc.hadm_id = ce.hadm_id
  WHERE ce.charttime BETWEEN vc.intime AND DATETIME_ADD(vc.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220179, 220045)
    AND ce.valuenum IS NOT NULL
  GROUP BY vc.stay_id
),

composite_scores AS (
  SELECT
    vc.*,
    v.hypotension_event,
    v.tachycardia_event,
    COALESCE(v.hypotension_event, 0) + COALESCE(v.tachycardia_event, 0) AS instability_score
  FROM vent_cohort vc
  LEFT JOIN vitals v
    ON vc.stay_id = v.stay_id
),

percentiles AS (
  SELECT DISTINCT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score,
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS p75_score
  FROM composite_scores
)

SELECT
  -- 90th percentile for the entire cohort
  (SELECT p90_score FROM percentiles) AS overall_90th_percentile_score,
  -- For the top 25% most unstable
  COUNT(*) AS top25_count,
  SUM(cs.hypotension_event) AS hypotension_count,
  SUM(cs.tachycardia_event) AS tachycardia_count,
  AVG(cs.los) AS avg_icu_los,
  SUM(cs.hospital_expire_flag) AS mortality_count,
  ROUND(SUM(cs.hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_percent
FROM composite_scores cs
CROSS JOIN percentiles p
WHERE cs.instability_score >= p.p75_score;