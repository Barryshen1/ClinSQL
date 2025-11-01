WITH stroke_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    i.los AS icu_los,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (
      (d.icd_version = 9 AND (
         (d.icd_code LIKE '433%' AND RIGHT(d.icd_code,1)='1')
         OR (d.icd_code LIKE '434%' AND RIGHT(d.icd_code,1)='1')
         OR d.icd_code = '436'
      ))
      OR (d.icd_version = 10 AND (
         d.icd_code LIKE 'I63%' OR d.icd_code = 'I64'
      ))
    )
),
vitals_first72 AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM stroke_cohort sc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON sc.stay_id = ce.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (
      220045, -- Heart Rate
      220179, -- Non Invasive BP systolic
      220180, -- Non Invasive BP diastolic
      220181, -- Non Invasive BP mean
      220210, -- Resp Rate
      220277, -- SPO2
      223761  -- Temperature C
    )
),
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(ABS(valuenum)) * 1.0 AS instability_score
  FROM vitals_first72
  GROUP BY subject_id, hadm_id, stay_id
),
cohort_with_scores AS (
  SELECT
    sc.*,
    s.instability_score
  FROM stroke_cohort sc
  JOIN instability_scores s
    ON sc.stay_id = s.stay_id
),
percentile_info AS (
  SELECT
    100 * SUM(CASE WHEN instability_score <= 80 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_80,
    PERCENTILE_CONT(instability_score, 0.75) AS q3_threshold
  FROM cohort_with_scores
),
top_quartile_stats AS (
  SELECT
    AVG(icu_los) AS avg_icu_los,
    100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM cohort_with_scores c
  CROSS JOIN percentile_info pi
  WHERE c.instability_score >= pi.q3_threshold
)
SELECT
  pi.percentile_of_80,
  tqs.avg_icu_los,
  tqs.mortality_rate
FROM percentile_info pi
CROSS JOIN top_quartile_stats tqs;