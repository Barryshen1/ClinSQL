WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays ie
    ON p.subject_id = ie.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 52 AND 62
),
cohort AS (
  SELECT DISTINCT
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    ie.los
  FROM patients_age pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays ie
    ON pa.subject_id = ie.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON ie.stay_id = pe.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%hemodialysis%'
     OR LOWER(di.label) LIKE '%continuous renal replacement%'
     OR LOWER(di.label) LIKE '%crrt%'
),
vital_labels AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) IN (
    'heart rate',
    'arterial blood pressure systolic',
    'non invasive blood pressure systolic',
    'respiratory rate',
    'spo2',
    'temperature'
  )
),
vitals_first_72h AS (
  SELECT
    ce.stay_id,
    ce.itemid,
    ce.valuenum,
    ce.charttime
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN vital_labels vl ON ce.itemid = vl.itemid
  INNER JOIN cohort c ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
),
abnormal_vitals AS (
  SELECT
    stay_id,
    SUM(
      CASE
        WHEN itemid IN (SELECT itemid FROM vital_labels WHERE LOWER(label) = 'heart rate') 
          AND (valuenum < 50 OR valuenum > 110) THEN 1
        WHEN itemid IN (SELECT itemid FROM vital_labels WHERE LOWER(label) LIKE '%systolic%') 
          AND (valuenum < 90 OR valuenum > 180) THEN 1
        WHEN itemid IN (SELECT itemid FROM vital_labels WHERE LOWER(label) = 'respiratory rate') 
          AND (valuenum < 10 OR valuenum > 25) THEN 1
        WHEN itemid IN (SELECT itemid FROM vital_labels WHERE LOWER(label) = 'spo2') 
          AND valuenum < 92 THEN 1
        WHEN itemid IN (SELECT itemid FROM vital_labels WHERE LOWER(label) = 'temperature') 
          AND (valuenum < 36.0 OR valuenum > 38.0) THEN 1
        ELSE 0
      END
    ) AS abnormal_count
  FROM vitals_first_72h
  GROUP BY stay_id
),
instability_scores AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    COALESCE(av.abnormal_count, 0) AS instability_score,
    c.los,
    a.hospital_expire_flag
  FROM cohort c
  LEFT JOIN abnormal_vitals av ON c.stay_id = av.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON c.hadm_id = a.hadm_id
),
percentile_calcs AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) AS p90_cutoff,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN instability_score <= 65 THEN 1 ELSE 0 END) AS count_le_65
  FROM instability_scores
),
score_stats AS (
  SELECT
    count_le_65 * 100.0 / total_patients AS percentile_of_65,
    p90_cutoff
  FROM percentile_calcs
),
top_decile_stats AS (
  SELECT
    AVG(los) AS mean_los_top_decile,
    AVG(hospital_expire_flag) AS mortality_top_decile
  FROM instability_scores
  CROSS JOIN percentile_calcs
  WHERE instability_score >= percentile_calcs.p90_cutoff
)
SELECT
  (SELECT percentile_of_65 FROM score_stats) AS percentile_of_65,
  (SELECT mean_los_top_decile FROM top_decile_stats) AS mean_los_top_decile,
  (SELECT mortality_top_decile FROM top_decile_stats) AS mortality_top_decile;