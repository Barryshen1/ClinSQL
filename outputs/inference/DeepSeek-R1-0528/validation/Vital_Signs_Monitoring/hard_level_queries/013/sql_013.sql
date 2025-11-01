WITH trauma_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code BETWEEN '800' AND '999') OR
    (icd_version = 10 AND (icd_code LIKE 'S%' OR icd_code LIKE 'T%'))
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT icd_code) >= 2
),
base_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - CAST(p.anchor_year AS INT)) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN trauma_admissions t
    ON i.hadm_id = t.hadm_id
  WHERE p.gender = 'M'
),
first_icu AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    icu_los,
    age_at_icu,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_num
  FROM base_cohort
  WHERE age_at_icu BETWEEN 68 AND 78
),
vitals AS (
  SELECT 
    f.stay_id,
    ce.itemid,
    ce.valuenum
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.stay_id = ce.stay_id
    AND ce.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220045, 220050, 220179, 220210)  -- HR, SBP (2 types), RR
    AND ce.valuenum IS NOT NULL
  WHERE f.stay_num = 1
),
cohort_vitals AS (
  SELECT 
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    f.icu_los,
    MAX(CASE WHEN v.itemid = 220045 THEN v.valuenum END) AS max_hr,
    MIN(CASE WHEN v.itemid IN (220050, 220179) THEN v.valuenum END) AS min_sbp,
    MAX(CASE WHEN v.itemid = 220210 THEN v.valuenum END) AS max_rr,
    COUNT(CASE WHEN v.itemid = 220045 AND v.valuenum > 100 THEN 1 END) AS tachycardia_episodes,
    COUNT(CASE WHEN v.itemid IN (220050, 220179) AND v.valuenum < 90 THEN 1 END) AS hypotension_episodes,
    COUNT(CASE WHEN v.itemid = 220210 AND v.valuenum > 20 THEN 1 END) AS tachypnea_episodes
  FROM first_icu f
  LEFT JOIN vitals v
    ON f.stay_id = v.stay_id
  WHERE f.stay_num = 1
  GROUP BY f.stay_id, f.subject_id, f.hadm_id, f.icu_los
),
cohort_score AS (
  SELECT 
    *,
    CASE WHEN max_hr > 100 THEN 1 ELSE 0 END +
    CASE WHEN min_sbp < 90 THEN 1 ELSE 0 END +
    CASE WHEN max_rr > 20 THEN 1 ELSE 0 END AS instability_score
  FROM cohort_vitals
),
final_cohort AS (
  SELECT 
    cs.*,
    a.hospital_expire_flag
  FROM cohort_score cs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cs.hadm_id = a.hadm_id
),
quartiles AS (
  SELECT 
    stay_id,
    instability_score,
    icu_los,
    hospital_expire_flag,
    tachycardia_episodes,
    hypotension_episodes,
    tachypnea_episodes,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM final_cohort
)
SELECT 
  'Quartile ' || CAST(quartile AS STRING) AS category,
  COUNT(*) AS count,
  AVG(instability_score) AS mean_score,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  NULL AS mean_tachycardia_episodes,
  NULL AS mean_hypotension_episodes,
  NULL AS mean_tachypnea_episodes
FROM quartiles
GROUP BY quartile
UNION ALL
SELECT 
  'Top Decile' AS category,
  NULL,
  NULL,
  NULL,
  NULL,
  AVG(tachycardia_episodes) AS mean_tachycardia_episodes,
  AVG(hypotension_episodes) AS mean_hypotension_episodes,
  AVG(tachypnea_episodes) AS mean_tachypnea_episodes
FROM quartiles
WHERE decile = 1
ORDER BY category;