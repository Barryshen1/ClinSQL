WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (LOWER(di.long_title) LIKE '%ischemic stroke%'
         OR LOWER(di.long_title) LIKE '%cerebral infarction%')
),

first_icu_stay AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN cohort c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
  WHERE i.intime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),

vital_signs AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    CASE 
      WHEN c.itemid = 220045 AND c.valuenum IS NOT NULL AND (c.valuenum < 40 OR c.valuenum > 130) THEN 1  -- Heart Rate
      WHEN c.itemid = 220050 AND c.valuenum IS NOT NULL AND (c.valuenum < 90 OR c.valuenum > 200) THEN 1  -- Systolic BP
      WHEN c.itemid = 220051 AND c.valuenum IS NOT NULL AND (c.valuenum < 60 OR c.valuenum > 120) THEN 1  -- Diastolic BP
      WHEN c.itemid = 220052 AND c.valuenum IS NOT NULL AND (c.valuenum < 70 OR c.valuenum > 140) THEN 1  -- Mean BP
      WHEN c.itemid = 220210 AND c.valuenum IS NOT NULL AND (c.valuenum < 8 OR c.valuenum > 35) THEN 1   -- Respiratory Rate
      WHEN c.itemid = 220277 AND c.valuenum IS NOT NULL AND c.valuenum < 90 THEN 1                       -- SpO2
      WHEN c.itemid = 223761 AND c.valuenum IS NOT NULL AND (c.valuenum < 35 OR c.valuenum > 39) THEN 1  -- Temperature
      ELSE 0
    END AS is_abnormal
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN first_icu_stay fis ON c.stay_id = fis.stay_id
  WHERE c.charttime >= fis.intime
    AND c.charttime <= TIMESTAMP_ADD(fis.intime, INTERVAL 72 HOUR)
),

instability_score AS (
  SELECT 
    fis.stay_id,
    fis.subject_id,
    fis.hadm_id,
    SUM(vs.is_abnormal) AS instability_score,
    fis.los
  FROM first_icu_stay fis
  LEFT JOIN vital_signs vs ON fis.stay_id = vs.stay_id
  GROUP BY fis.stay_id, fis.subject_id, fis.hadm_id, fis.los
),

mortality_data AS (
  SELECT 
    iscore.subject_id,
    iscore.hadm_id,
    iscore.instability_score,
    iscore.los,
    a.hospital_expire_flag
  FROM instability_score iscore
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a 
    ON iscore.subject_id = a.subject_id AND iscore.hadm_id = a.hadm_id
),

percentile_80 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.75) OVER () AS p75_score
  FROM mortality_data
  WHERE instability_score IS NOT NULL
  LIMIT 1
),

top_quartile AS (
  SELECT 
    md.instability_score,
    md.los,
    md.hospital_expire_flag
  FROM mortality_data md
  CROSS JOIN percentile_80 p
  WHERE md.instability_score >= p.p75_score
)

SELECT 
  (SELECT PERCENT_RANK() OVER (ORDER BY instability_score) * 100 
   FROM mortality_data 
   WHERE instability_score = 80 
   LIMIT 1) AS percentile_of_80,
  AVG(tq.los) AS avg_icu_los_top_quartile,
  AVG(tq.hospital_expire_flag) AS mortality_rate_top_quartile
FROM top_quartile tq
WHERE tq.instability_score IS NOT NULL;