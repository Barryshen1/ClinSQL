WITH first_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (subject_id, hadm_id)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),
multi_trauma AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    USING (icd_code, icd_version)
  WHERE LOWER(dd.long_title) LIKE '%trauma%'
),
cohort AS (
  SELECT f.*
  FROM first_icustays f
  JOIN multi_trauma mt
    USING (subject_id, hadm_id)
  WHERE f.gender = 'M'
    AND f.anchor_age BETWEEN 68 AND 78
),
chartevents_vitals AS (
  SELECT
    c.stay_id,
    ce.itemid,
    ce.valuenum,
    ce.charttime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    USING (subject_id, hadm_id, stay_id)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND (
      LOWER(d.label) LIKE '%heart rate%' OR
      LOWER(d.label) LIKE '%respiratory rate%' OR
      LOWER(d.label) LIKE '%systolic blood pressure%'
    )
),
instability_flags AS (
  SELECT
    stay_id,
    SUM(CASE WHEN LOWER(d.label) LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN LOWER(d.label) LIKE '%systolic blood pressure%' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN LOWER(d.label) LIKE '%respiratory rate%' AND ce.valuenum > 24 THEN 1 ELSE 0 END) AS tachypnea_count
  FROM chartevents_vitals ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  GROUP BY stay_id
),
scores AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.los,
    c.hospital_expire_flag,
    f.tachycardia_count,
    f.hypotension_count,
    f.tachypnea_count,
    (f.tachycardia_count + f.hypotension_count + f.tachypnea_count) AS instability_score
  FROM cohort c
  LEFT JOIN instability_flags f
    USING (stay_id)
),
quartiles AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY instability_score) AS quartile,
         NTILE(10) OVER (ORDER BY instability_score) AS decile
  FROM scores
),
quartile_stats AS (
  SELECT
    quartile,
    COUNT(*) AS n_patients,
    AVG(instability_score) AS mean_score,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM quartiles
  GROUP BY quartile
  ORDER BY quartile
),
top_decile AS (
  SELECT
    AVG(tachycardia_count) AS mean_tachycardia,
    AVG(hypotension_count) AS mean_hypotension,
    AVG(tachypnea_count) AS mean_tachypnea
  FROM quartiles
  WHERE decile = 10
)
SELECT 'quartile_stats' AS table_name, * 
FROM quartile_stats
UNION ALL
SELECT 'top_decile', NULL, NULL, NULL, NULL, mean_tachycardia
FROM top_decile;