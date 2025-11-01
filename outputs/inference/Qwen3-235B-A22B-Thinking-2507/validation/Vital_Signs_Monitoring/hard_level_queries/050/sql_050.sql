WITH cohort_base AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.los,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = i.stay_id
        AND pe.starttime BETWEEN i.intime AND i.outtime
        AND pe.itemid IN (225802, 225803, 225809)  -- RRT procedure codes
    )
),
vital_signs_abnormal AS (
  SELECT 
    ce.stay_id,
    COUNT(*) AS abnormal_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.stay_id IN (SELECT stay_id FROM cohort_base)
    AND ce.charttime BETWEEN i.intime AND i.intime + INTERVAL '72' HOUR
    AND ce.valuenum IS NOT NULL
    AND di.lownormalvalue IS NOT NULL
    AND di.highnormalvalue IS NOT NULL
    AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)
  GROUP BY ce.stay_id
),
cohort_scores AS (
  SELECT 
    cb.*,
    COALESCE(v.abnormal_count, 0) AS instability_score
  FROM cohort_base cb
  LEFT JOIN vital_signs_abnormal v
    ON cb.stay_id = v.stay_id
),
cohort_with_decile AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM cohort_scores
)
SELECT 
  (COUNTIF(instability_score <= 65) * 100.0 / COUNT(*)) AS percentile_65,
  AVG(CASE WHEN decile = 1 THEN los END) AS mean_los_top_decile,
  AVG(CASE WHEN decile = 1 THEN hospital_expire_flag END) AS mortality_rate_top_decile
FROM cohort_with_decile;