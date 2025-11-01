WITH
-- 1) Identify ACS-ICU case admissions (female, age 67-77, ICU stay, ACS diagnosis)
acs_icu_case AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender,
    i.stay_id AS icu_stay_id,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 67 AND 77
),

-- 1a) ACS diagnosis flags per admission (covering AMI, unstable angina, ACS)
acs_diagnosis AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.deathtime,
    ca.icu_los,
    -- We'll derive an ACS flag using long_title matching
    MAX(CASE
          WHEN LOWER(d.long_title) LIKE '%acute myocardial infarction%' THEN 1
          WHEN LOWER(d.long_title) LIKE '%unstable angina%' THEN 1
          WHEN LOWER(d.long_title) LIKE '%acute coronary syndrome%' THEN 1
          ELSE 0
        END) AS has_acs
  FROM acs_icu_case AS ca
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = ca.subject_id AND di.hadm_id = ca.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY ca.subject_id, ca.hadm_id, ca.admittime, ca.deathtime, ca.icu_los
),

-- 1b) Approximate Charlson score per admission (case)
charlson_case AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    SUM(
      CAST(LOWER(d.long_title) LIKE '%myocardial infarction%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%congestive heart failure%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%peripheral vascular%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%cerebrovascular%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%dementia%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%diabetes%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%diabetes with complications%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%renal%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%liver%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%malignancy%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%metastatic%' AS INT64) * 6
    ) AS charlson_score
  FROM acs_diagnosis ca
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = ca.subject_id AND di.hadm_id = ca.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY a.subject_id, a.hadm_id
),

-- 1c) 30-day mortality flag for ACS-ICU case
mortality_case AS (
  SELECT
    cc.subject_id,
    cc.hadm_id,
    cc.admittime,
    cc.deathtime,
    cc.icu_los,
    cc.charlson_score,
    CASE
      WHEN cc.deathtime IS NOT NULL
           AND DATE(cc.deathtime) <= DATE_ADD(DATE(cc.admittime), INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS died_within_30d
  FROM charlson_case AS cc
  JOIN acs_diagnosis AS ad
    ON ad.subject_id = cc.subject_id AND ad.hadm_id = cc.hadm_id
  WHERE ad.has_acs = 1
),

-- 1d) Cardiac and neurologic complication flags for ACS-ICU case
complications_case AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.deathtime,
    m.icu_los,
    m.charlson_score,
    m.died_within_30d,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%myocardial infarction%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%arrhythmia%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%cardiac arrest%' THEN 1 ELSE 0 END) AS cardiac_comp_flag,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%stroke%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%cerebrovascular%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%delirium%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%encephalopathy%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%seizure%' THEN 1 ELSE 0 END) AS neuro_comp_flag
  FROM mortality_case AS m
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = m.subject_id AND di.hadm_id = m.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY m.subject_id, m.hadm_id, m.admittime, m.deathtime, m.icu_los, m.charlson_score, m.died_within_30d
),

case_summary AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.deathtime,
    c.icu_los,
    c.charlson_score,
    c.died_within_30d,
    cc.cardiac_comp_flag,
    cc.neuro_comp_flag
  FROM mortality_case AS c
  JOIN complications_case AS cc
    ON cc.subject_id = c.subject_id AND cc.hadm_id = c.hadm_id
),

-- 2) Age-matched general inpatient reference cohort (female, age 67-77, no ICU)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 67 AND 77
    -- exclude ICU admissions for the general inpatient baseline
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    )
),

-- 2a) Charlson score for general inpatients
general_chars AS (
  SELECT
    gi.subject_id,
    gi.hadm_id,
    gi.admittime,
    gi.dischtime,
    SUM(
      CAST(LOWER(d.long_title) LIKE '%myocardial infarction%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%congestive heart failure%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%peripheral vascular%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%cerebrovascular%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%dementia%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%diabetes%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%renal%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%liver%' AS INT64) +
      CAST(LOWER(d.long_title) LIKE '%malignancy%' AS INT64)
    ) AS charlson_score
  FROM general_inpatients AS gi
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = gi.subject_id AND di.hadm_id = gi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY gi.subject_id, gi.hadm_id, gi.admittime, gi.dischtime
),

-- 2b) complications for general inpatients (same patterns)
general_comp AS (
  SELECT
    gh.subject_id,
    gh.hadm_id,
    gh.admittime,
    gh.dischtime,
    gh.deathtime,
    gh.charlson_score,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%myocardial infarction%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%arrhythmia%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%cardiac arrest%' THEN 1 ELSE 0 END) AS cardiac_comp_flag,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%stroke%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%cerebrovascular%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%delirium%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%encephalopathy%' THEN 1 ELSE 0 END
        + CASE WHEN LOWER(d.long_title) LIKE '%seizure%' THEN 1 ELSE 0 END) AS neuro_comp_flag
  FROM general_chars gh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = gh.subject_id AND di.hadm_id = gh.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY gh.subject_id, gh.hadm_id, gh.admittime, gh.dischtime, gh.deathtime, gh.charlson_score
)

SELECT
  -- Case (ACS+ICU)
  (SELECT AVG(charlson_score) FROM (
     SELECT c.charlson_score
     FROM case_summary cs
     JOIN (
       SELECT subject_id, hadm_id, charlson_score
       FROM case_summary
     ) c ON c.subject_id = cs.subject_id AND c.hadm_id = cs.hadm_id
  )) AS mean_case_risk_score,
  (SELECT AVG(died_within_30d) FROM case_summary cs) AS case_30d_mortality_rate,
  (SELECT AVG(cardiac_comp_flag) FROM complications_case) AS case_cardio_comp_rate,
  (SELECT AVG(neuro_comp_flag) FROM complications_case) AS case_neuro_comp_rate,
  (SELECT AVG(los) FROM (
      SELECT icu_los AS los
      FROM case_summary
      WHERE died_within_30d = 0
  )) AS case_survivor_mean_icu_los,

  -- General inpatient comparisons
  (SELECT AVG(COALESCE(cardiac_comp_flag,0)) FROM general_comp gc
     JOIN general_inpatients gi ON gi.subject_id = gc.subject_id AND gi.hadm_id = gc.hadm_id) AS general_cardio_comp_rate,
  (SELECT AVG(COALESCE(neuro_comp_flag,0)) FROM general_comp gc
     JOIN general_inpatients gi ON gi.subject_id = gc.subject_id AND gi.hadm_id = gc.hadm_id) AS general_neuro_comp_rate,
  (SELECT AVG(los) FROM (
     SELECT DATE_DIFF(dischtime, admittime, DAY) AS los
     FROM general_inpatients
     WHERE NOT EXISTS (
       SELECT 1
       FROM `physionet-data.mimiciv_3_1_icu.icustays` i
       WHERE i.subject_id = general_inpatients.subject_id AND i.hadm_id = general_inpatients.hadm_id
     )
     AND deathtime IS NULL  -- survivors only
  )) AS general_survivor_mean_hospital_los,

  -- Matched-profile percentile
  -- Case Charlson score percentile among general inpatients
  (SELECT
     100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM general_inpatients), 0)
   FROM general_inpatients g
   WHERE g.charlson_score <= (SELECT cc.charlson_score
                             FROM charlson_case cc
                             JOIN acs_diagnosis ad ON ad.subject_id = cc.subject_id AND ad.hadm_id = cc.hadm_id
                             LIMIT 1)
  ) AS matched_profile_percentile
;