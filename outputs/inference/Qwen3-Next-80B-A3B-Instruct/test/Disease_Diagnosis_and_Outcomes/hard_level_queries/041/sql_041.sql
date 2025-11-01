WITH ich_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    di.long_title AS diagnosis,
    i.stay_id,
    t.careunit,
    t.eventtype,
    t.intime AS icu_intime,
    t.outtime AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_cd ON a.hadm_id = di_cd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON di_cd.icd_code = di.icd_code AND di_cd.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t ON p.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  WHERE p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'M'
    AND (
      LOWER(di.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(di.long_title) LIKE '%intracerebral hemorrhage%'
      OR LOWER(di.long_title) LIKE '%subarachnoid hemorrhage%'
      OR LOWER(di.long_title) LIKE '%other nontraumatic intracranial hemorrhage%'
    )
    AND t.eventtype = 'transfer'
    AND t.careunit LIKE 'ICU%'
),
mortality_30d AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL AND deathtime <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      WHEN deathtime IS NULL AND dod IS NOT NULL AND dod <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS died_30d
  FROM ich_cohort
),
aki_ards AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN LOWER(di2.long_title) LIKE '%acute kidney injury%' OR LOWER(di2.long_title) LIKE '%acute renal failure%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN LOWER(di2.long_title) LIKE '%acute respiratory distress syndrome%' OR LOWER(di2.long_title) LIKE '%ards%' THEN 1 ELSE 0 END) AS has_ards
  FROM ich_cohort ic
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_cd2 ON ic.hadm_id = di_cd2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di2 ON di_cd2.icd_code = di2.icd_code AND di_cd2.icd_version = di2.icd_version
  GROUP BY subject_id, hadm_id
),
survival_decedents AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    COALESCE(deathtime, dod) AS death_time,
    DATETIME_DIFF(COALESCE(deathtime, dod), admittime, DAY) AS survival_days
  FROM ich_cohort
  WHERE deathtime IS NOT NULL OR dod IS NOT NULL
)
SELECT
  COUNT(*) AS cohort_size,
  AVG(m.died_30d) AS thirty_day_mortality_rate,
  AVG(a.has_aki) AS aki_rate,
  AVG(a.has_ards) AS ards_rate,
  -- Composite risk score omitted per instructions
  (SELECT PERCENTILE_CONT(survival_days, 0.5) FROM survival_decedents) AS median_survival_days_decedents
FROM ich_cohort ic
JOIN mortality_30d m ON ic.subject_id = m.subject_id AND ic.hadm_id = m.hadm_id
JOIN aki_ards a ON ic.subject_id = a.subject_id AND ic.hadm_id = a.hadm_id;