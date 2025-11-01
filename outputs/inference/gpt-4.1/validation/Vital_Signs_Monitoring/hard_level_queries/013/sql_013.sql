WITH trauma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(icd_code, r'^(S|T)[0-9]{2,}')
),
multi_trauma_admissions AS (
  SELECT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN (SELECT icd_code FROM trauma_codes)
  GROUP BY subject_id, hadm_id
  HAVING COUNT(DISTINCT icd_code) >= 2
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
)
, cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    f.stay_id,
    p.anchor_age,
    p.gender,
    f.icu_intime,
    f.icu_outtime,
    f.los,
    a.hospital_expire_flag
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON f.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
  JOIN multi_trauma_admissions mta ON f.subject_id = mta.subject_id AND f.hadm_id = mta.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND f.rn = 1
)
, itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%' THEN itemid END) AS hr_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%systolic blood pressure%' THEN itemid END) AS sbp_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%respiratory rate%' THEN itemid END) AS rr_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
)
, vitals_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    c.icu_intime,
    c.icu_outtime,
    -- Flags for instability
    CASE WHEN ce.itemid = i.hr_itemid AND ce.valuenum > 120 THEN 1 ELSE 0 END AS tachycardia,
    CASE WHEN ce.itemid = i.sbp_itemid AND ce.valuenum < 90 THEN 1 ELSE 0 END AS hypotension,
    CASE WHEN ce.itemid = i.rr_itemid AND ce.valuenum > 30 THEN 1 ELSE 0 END AS tachypnea
  FROM cohort c
  CROSS JOIN itemids i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id AND c.stay_id = ce.stay_id
  WHERE ce.itemid IN (i.hr_itemid, i.sbp_itemid, i.rr_itemid)
    AND ce.charttime BETWEEN c.icu_intime AND TIMESTAMP_ADD(c.icu_intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
)
, instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNTIF(tachycardia=1 OR hypotension=1 OR tachypnea=1) AS instability_score,
    COUNTIF(tachycardia=1) AS tachycardia_episodes,
    COUNTIF(hypotension=1) AS hypotension_episodes,
    COUNTIF(tachypnea=1) AS tachypnea_episodes
  FROM vitals_24h
  GROUP BY subject_id, hadm_id, stay_id
)
, final AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.anchor_age,
    c.gender,
    c.los,
    c.hospital_expire_flag,
    s.instability_score,
    s.tachycardia_episodes,
    s.hypotension_episodes,
    s.tachypnea_episodes,
    NTILE(4) OVER (ORDER BY s.instability_score) AS quartile,
    NTILE(10) OVER (ORDER BY s.instability_score) AS decile
  FROM cohort c
  JOIN instability_scores s
    ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
)
SELECT
  -- Part 1: Quartile summary
  ARRAY(
    SELECT AS STRUCT
      quartile,
      COUNT(*) AS n_patients,
      ROUND(AVG(instability_score),2) AS mean_instability_score,
      ROUND(AVG(los),2) AS mean_icu_los,
      ROUND(AVG(hospital_expire_flag),3) AS mortality_rate
    FROM final
    GROUP BY quartile
    ORDER BY quartile
  ) AS quartile_summary,
  -- Part 2: Top decile vital instability episodes
  (
    SELECT AS STRUCT
      ROUND(AVG(tachycardia_episodes),2) AS mean_tachycardia_episodes,
      ROUND(AVG(hypotension_episodes),2) AS mean_hypotension_episodes,
      ROUND(AVG(tachypnea_episodes),2) AS mean_tachypnea_episodes
    FROM final
    WHERE decile = 10
  ) AS top_decile_vital_instability
;