WITH
-- 1) All female admissions aged 43-53
female_43_53_adm AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),

-- 2) Admissions with at least one ICU stay
icu_adm_43_53 AS (
  SELECT DISTINCT f.hadm_id, f.subject_id, f.admittime, f.dischtime, f.deathtime
  FROM female_43_53_adm AS f
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.hadm_id = f.hadm_id
),

-- 3) Heart failure admissions among the ICU subset (hadm_id with HF diagnosis)
hf_adm AS (
  SELECT DISTINCT i.hadm_id
  FROM icu_adm_43_53 AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

-- 4) Risk flags per hadm_id (diabetes, renal, liver, pulm, malignancy)
risk_flags AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%renal failure%' OR LOWER(dd.long_title) LIKE '%kidney failure%' THEN 1 ELSE 0 END) AS has_renal_failure,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%hepatic failure%' OR LOWER(dd.long_title) LIKE '%liver failure%' OR LOWER(dd.long_title) LIKE '%cirrhosis%' THEN 1 ELSE 0 END) AS has_liver_failure,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%' OR LOWER(dd.long_title) LIKE '%emphysema%' THEN 1 ELSE 0 END) AS has_pulm_disease,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cancer%' OR LOWER(dd.long_title) LIKE '%malignancy%' THEN 1 ELSE 0 END) AS has_malignancy
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),

risk_by_hadm AS (
  SELECT rf.hadm_id,
         (COALESCE(rf.has_diabetes,0) +
          COALESCE(rf.has_renal_failure,0) +
          COALESCE(rf.has_liver_failure,0) +
          COALESCE(rf.has_pulm_disease,0) +
          COALESCE(rf.has_malignancy,0)) AS risk_score
  FROM risk_flags rf
  RIGHT JOIN hf_adm hf
    ON rf.hadm_id = hf.hadm_id
),

-- 5) Major complications per admission (proxy: AKI, respiratory failure, sepsis, MI, stroke, cardiac arrest)
major_comp AS (
  SELECT di.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute kidney injury%' THEN 1 ELSE 0 END) AS aki,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%respiratory failure%' OR LOWER(dd.long_title) LIKE '%acute respiratory failure%' THEN 1 ELSE 0 END) AS resp_fail,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%' OR LOWER(dd.long_title) LIKE '%septic%' THEN 1 ELSE 0 END) AS sepsis,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%' OR LOWER(dd.long_title) LIKE '%infarction%' THEN 1 ELSE 0 END) AS mi,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%stroke%' OR LOWER(dd.long_title) LIKE '%cerebrovascular%' THEN 1 ELSE 0 END) AS stroke,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cardiac arrest%' THEN 1 ELSE 0 END) AS cardiac_arrest
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),
major_comp_flag AS (
  SELECT m.hadm_id,
         CASE
           WHEN (COALESCE(m.aki,0) + COALESCE(m.resp_fail,0) + COALESCE(m.sepsis,0) + COALESCE(m.mi,0) + COALESCE(m.stroke,0) + COALESCE(m.cardiac_arrest,0)) > 0
           THEN 1 ELSE 0 END AS major_comp
  FROM major_comp m
),

-- 6) Build per-admissionLOS and death info for the final cohort
cohort_los AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    CASE
      WHEN a.deathtime IS NOT NULL THEN CAST(a.deathtime AS TIMESTAMP)
      WHEN p2.dod IS NOT NULL THEN CAST(p2.dod AS TIMESTAMP)
      ELSE NULL
    END AS death_ts,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0 AS los_days
  FROM icu_adm_43_53 AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p2
    ON p2.subject_id = h.subject_id
),

-- 7) Final aggregation: compute requested metrics
,results AS (
  SELECT
    -- risk_score median and IQR for the cohort
    (SELECT APPROX_QUANTILES(rs.risk_score, 4)[OFFSET(2)]
     FROM risk_by_hadm rs
     JOIN hf_adm hf ON hf.hadm_id = rs.hadm_id) AS median_risk_score,
    (SELECT (APPROX_QUANTILES(rs.risk_score, 4)[OFFSET(3)] - APPROX_QUANTILES(rs.risk_score, 4)[OFFSET(1)])
     FROM risk_by_hadm rs
     JOIN hf_adm hf ON hf.hadm_id = rs.hadm_id) AS iqr_risk_score,

    -- 30-day mortality rate
    (SELECT AVG(
              CASE WHEN cl.death_ts IS NOT NULL AND cl.death_ts <= cl.admittime + INTERVAL 30 DAY
                   THEN 1 ELSE 0 END)
     FROM cohort_los cl
     JOIN hf_adm hf ON hf.hadm_id = cl.hadm_id) AS thirty_day_mortality_rate,

    -- major complication rate
    (SELECT AVG(
              CASE WHEN mc.major_comp = 1 THEN 1 ELSE 0 END)
     FROM cohort_los cl
     JOIN major_comp_flag mc ON mc.hadm_id = cl.hadm_id
     WHERE cl.hadm_id IS NOT NULL) AS major_complication_rate,

    -- average LOS among survivors (not dead within 30 days)
    (SELECT AVG(los_days)
     FROM cohort_los cl
     WHERE NOT (cl.death_ts IS NOT NULL AND cl.death_ts <= cl.admittime + INTERVAL 30 DAY)) AS avg_los_survivors_days
)

SELECT *
FROM results;