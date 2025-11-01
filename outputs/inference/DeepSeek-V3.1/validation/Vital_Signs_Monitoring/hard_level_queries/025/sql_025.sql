WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ie.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I46%') 
      OR (diag.icd_version = 9 AND diag.icd_code = '427.5')
    )
),

vitals_first_24h AS (
  SELECT 
    c.stay_id,
    ce.itemid,
    -- Extract numeric values
    AVG(ce.valuenum) AS avg_value,
    STDDEV(ce.valuenum) AS sd_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220045, 220179, 220180, 220181, 220210, 220277)  -- HR, SBP, DBP, MBP, RR, SpO2
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id, ce.itemid
),

vitals_agg AS (
  SELECT 
    stay_id,
    -- Pivot the SD values for each vital sign
    MAX(CASE WHEN itemid = 220045 THEN sd_value END) AS sd_hr,
    MAX(CASE WHEN itemid = 220179 THEN sd_value END) AS sd_sbp,
    MAX(CASE WHEN itemid = 220180 THEN sd_value END) AS sd_dbp,
    MAX(CASE WHEN itemid = 220181 THEN sd_value END) AS sd_mbp,
    MAX(CASE WHEN itemid = 220210 THEN sd_value END) AS sd_rr,
    MAX(CASE WHEN itemid = 220277 THEN sd_value END) AS sd_spo2
  FROM vitals_first_24h
  GROUP BY stay_id
),

-- Calculate z-scores for each SD relative to the cohort
cohort_sd_stats AS (
  SELECT
    AVG(sd_hr) AS mean_sd_hr,
    STDDEV(sd_hr) AS std_sd_hr,
    AVG(sd_sbp) AS mean_sd_sbp,
    STDDEV(sd_sbp) AS std_sd_sbp,
    AVG(sd_dbp) AS mean_sd_dbp,
    STDDEV(sd_dbp) AS std_sd_dbp,
    AVG(sd_mbp) AS mean_sd_mbp,
    STDDEV(sd_mbp) AS std_sd_mbp,
    AVG(sd_rr) AS mean_sd_rr,
    STDDEV(sd_rr) AS std_sd_rr,
    AVG(sd_spo2) AS mean_sd_spo2,
    STDDEV(sd_spo2) AS std_sd_spo2
  FROM vitals_agg
),

instability_scores AS (
  SELECT
    va.stay_id,
    -- Calculate z-score for each SD and sum them (instability score)
    ( (sd_hr - mean_sd_hr) / std_sd_hr +
      (sd_sbp - mean_sd_sbp) / std_sd_sbp +
      (sd_dbp - mean_sd_dbp) / std_sd_dbp +
      (sd_mbp - mean_sd_mbp) / std_sd_mbp +
      (sd_rr - mean_sd_rr) / std_sd_rr +
      (sd_spo2 - mean_sd_spo2) / std_sd_spo2
    ) AS instability_score
  FROM vitals_agg va
  CROSS JOIN cohort_sd_stats css
),

cohort_with_scores AS (
  SELECT
    c.*,
    i.instability_score,
    -- Partition into deciles
    NTILE(10) OVER (ORDER BY i.instability_score DESC) AS instability_decile
  FROM cohort c
  LEFT JOIN instability_scores i
    ON c.stay_id = i.stay_id
)

-- Main query
SELECT
  -- For the given score (70), find its percentile
  (SELECT PERCENT_RANK() OVER (ORDER BY instability_score) 
   FROM cohort_with_scores 
   WHERE instability_score <= 70 
   ORDER BY instability_score DESC 
   LIMIT 1) AS percentile_of_70,

  -- For the most unstable decile (decile=1)
  (SELECT AVG(icu_los) 
   FROM cohort_with_scores 
   WHERE instability_decile = 1) AS mean_icu_los_top_decile,

  (SELECT AVG(hospital_expire_flag) 
   FROM cohort_with_scores 
   WHERE instability_decile = 1) AS mortality_rate_top_decile

FROM cohort_with_scores
LIMIT 1;