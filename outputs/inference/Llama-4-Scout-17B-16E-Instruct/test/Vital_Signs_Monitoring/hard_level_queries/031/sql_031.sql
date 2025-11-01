WITH 
-- Define post-op male patients aged 63-73
post_op_males AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admission_type,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_type = 'Elective'
),

-- Identify ICU stays for post-op males
post_op_male_icustays AS (
  SELECT 
    istay.subject_id,
    istay.hadm_id,
    istay.stay_id,
    istay.intime,
    istay.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` istay
  JOIN 
    post_op_males pom
  ON 
    istay.hadm_id = pom.hadm_id
),

-- Calculate instability score components
instability_scores AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    COUNT(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 38.5 THEN 1 END) AS fever_count,
    COUNT(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1 END) AS spo2_low_count,
    COUNT(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 20 THEN 1 END) AS rr_high_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  GROUP BY 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id
),

-- Calculate total instability score
instability_total AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    fever_count,
    spo2_low_count,
    rr_high_count,
    (fever_count + spo2_low_count + rr_high_count) AS total_instability_score
  FROM 
    instability_scores
),

-- Identify top quartile of instability
top_quartile AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    fever_count,
    spo2_low_count,
    rr_high_count,
    total_instability_score
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      fever_count,
      spo2_low_count,
      rr_high_count,
      total_instability_score,
      PERCENT_RANK() OVER (ORDER BY total_instability_score) AS percentile
    FROM 
      instability_total
  ) AS subquery
  WHERE 
    percentile >= 0.75
),

-- Calculate 95th percentile instability score
percentile_95 AS (
  SELECT 
    APPROX_QUANTILES(total_instability_score, 0.95)[OFFSET(1)] AS percentile_95_score
  FROM 
    instability_total
)

-- Compare clinical outcomes
SELECT 
  (SELECT percentile_95_score FROM percentile_95) AS percentile_95_score,
  AVG(TIMESTAMP_DIFF(i.outtime, i.intime, 'SECOND') / 3600) AS avg_icu_los,
  SUM(a.hospital_expire_flag) / COUNT(*) AS in_hospital_mortality
FROM 
  top_quartile tq
JOIN 
  post_op_male_icustays pomi
ON 
  tq.hadm_id = pomi.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` i
ON 
  pomi.stay_id = i.stay_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON 
  pomi.hadm_id = a.hadm_id;