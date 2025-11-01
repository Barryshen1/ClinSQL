WITH base_cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.outtime, 
    i.los,
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = i.subject_id AND d.hadm_id = i.hadm_id
        AND d.icd_code LIKE 'I63%'
    )
),
vital_signs AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    ce.itemid,
    ce.valuenum,
    ce.charttime
  FROM base_cohort i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id AND i.hadm_id = ce.hadm_id AND i.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN i.intime AND i.intime + INTERVAL 72 HOUR
    AND ce.itemid IN (
        -- Heart rate
        211, 220045,
        -- Systolic BP
        442, 456, 51, 52, 6701, 220050,
        -- Temperature
        676, 678, 223761, 223762,
        -- Respiratory rate
        220, 615, 220210
      )
    AND ce.valuenum IS NOT NULL
    AND (
      (ce.itemid IN (211, 220045) AND ce.valuenum BETWEEN 40 AND 200) -- HR
      OR (ce.itemid IN (442, 456, 51, 52, 6701, 220050) AND ce.valuenum BETWEEN 50 AND 250) -- SBP
      OR (ce.itemid IN (676, 678, 223761, 223762) AND ce.valuenum BETWEEN 34 AND 45) -- Temp in F
      OR (ce.itemid IN (220, 615, 220210) AND ce.valuenum BETWEEN 5 AND 50) -- RR
    )
),
vital_stats AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    AVG(CASE WHEN itemid IN (211, 220045) THEN valuenum ELSE NULL END) AS hr_mean,
    STDDEV(CASE WHEN itemid IN (211, 220045) THEN valuenum ELSE NULL END) AS hr_std,
    AVG(CASE WHEN itemid IN (442, 456, 51, 52, 6701, 220050) THEN valuenum ELSE NULL END) AS sbp_mean,
    STDDEV(CASE WHEN itemid IN (442, 456, 51, 52, 6701, 220050) THEN valuenum ELSE NULL END) AS sbp_std,
    AVG(CASE WHEN itemid IN (676, 678, 223761, 223762) THEN valuenum ELSE NULL END) AS temp_mean,
    STDDEV(CASE WHEN itemid IN (676, 678, 223761, 223762) THEN valuenum ELSE NULL END) AS temp_std,
    AVG(CASE WHEN itemid IN (220, 615, 220210) THEN valuenum ELSE NULL END) AS rr_mean,
    STDDEV(CASE WHEN itemid IN (220, 615, 220210) THEN valuenum ELSE NULL END) AS rr_std
  FROM vital_signs
  GROUP BY stay_id, subject_id, hadm_id
),
instability_scores AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    (COALESCE(hr_std,0) + COALESCE(sbp_std,0) + COALESCE(temp_std,0) + COALESCE(rr_std,0)) / 4.0 AS instability_score
  FROM vital_stats
),
cohort_with_score AS (
  SELECT 
    b.*,
    s.instability_score
  FROM base_cohort b
  LEFT JOIN instability_scores s
    ON b.stay_id = s.stay_id
),
dist AS (
  SELECT instability_score
  FROM cohort_with_score
  WHERE instability_score IS NOT NULL
),
percentile_of_80 AS (
  SELECT 
    (SELECT COUNT(*) FROM dist WHERE instability_score <= 80) * 100.0 / (SELECT COUNT(*) FROM dist) AS percentile
),
top_quartile AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    los,
    hospital_expire_flag
  FROM cohort_with_score
  WHERE instability_score >= (
    SELECT APPROX_QUANTILES(instability_score, 4)[SAFE_OFFSET(3)] 
    FROM cohort_with_score
    WHERE instability_score IS NOT NULL
  )
),
top_quartile_stats AS (
  SELECT 
    AVG(los) AS avg_los,
    SUM(CAST(hospital_expire_flag AS INT)) * 100.0 / COUNT(*) AS mortality_rate
  FROM top_quartile
)
SELECT percentile, NULL AS avg_los, NULL AS mortality_rate FROM percentile_of_80
UNION ALL
SELECT NULL, avg_los, mortality_rate FROM top_quartile_stats;