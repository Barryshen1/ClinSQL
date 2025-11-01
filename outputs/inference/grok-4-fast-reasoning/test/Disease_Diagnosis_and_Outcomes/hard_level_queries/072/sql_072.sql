WITH patients_female_age AS (
  SELECT subject_id, anchor_age, dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 67 AND 77
),
admissions_with_icu AS (
  SELECT a.*, p.dod, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_female_age p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id AND a.subject_id = i.subject_id
),
acs_adms AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag, a.dod, a.anchor_age
  FROM admissions_with_icu a
  WHERE EXISTS (
    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410.%' OR d.icd_code = '411.1'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21.%' OR d.icd_code = 'I20.0'))
    )
  )
),
first_acs_adm AS (
  SELECT subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, dod, anchor_age
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM acs_adms
  )
  WHERE rn = 1
),
first_general_adm AS (
  SELECT subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, dod, anchor_age
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM admissions_with_icu
  )
  WHERE rn = 1
),
acs_stats AS (
  SELECT
    COUNT(*) AS n_acs,
    AVG(anchor_age) AS mean_age_acs,
    AVG(CASE WHEN dod IS NOT NULL AND dod <= DATE(TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)) THEN 1.0 ELSE 0 END) AS mort_30d_acs,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 ELSE NULL END) AS los_survivors_acs,
    AVG(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      WHERE dd.hadm_id = first_acs_adm.hadm_id
      AND (
        (dd.icd_version = 9 AND (dd.icd_code LIKE '427%' OR dd.icd_code LIKE '428%'))
        OR (dd.icd_version = 10 AND (dd.icd_code LIKE 'I47%' OR dd.icd_code LIKE 'I48%' OR dd.icd_code LIKE 'I49%' OR dd.icd_code LIKE 'I50%'))
      )
    ) THEN 1.0 ELSE 0 END) AS cardiac_rate_acs,
    AVG(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      WHERE dd.hadm_id = first_acs_adm.hadm_id
      AND (
        (dd.icd_version = 9 AND dd.icd_code LIKE '43%')
        OR (dd.icd_version = 10 AND dd.icd_code LIKE 'I63%')
      )
    ) THEN 1.0 ELSE 0 END) AS neuro_rate_acs
  FROM first_acs_adm
),
general_stats AS (
  SELECT
    COUNT(*) AS n_gen,
    AVG(anchor_age) AS mean_age_gen,
    AVG(CASE WHEN dod IS NOT NULL AND dod <= DATE(TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)) THEN 1.0 ELSE 0 END) AS mort_30d_gen,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 ELSE NULL END) AS los_survivors_gen,
    AVG(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      WHERE dd.hadm_id = first_general_adm.hadm_id
      AND (
        (dd.icd_version = 9 AND (dd.icd_code LIKE '427%' OR dd.icd_code LIKE '428%'))
        OR (dd.icd_version = 10 AND (dd.icd_code LIKE 'I47%' OR dd.icd_code LIKE 'I48%' OR dd.icd_code LIKE 'I49%' OR dd.icd_code LIKE 'I50%'))
      )
    ) THEN 1.0 ELSE 0 END) AS cardiac_rate_gen,
    AVG(CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      WHERE dd.hadm_id = first_general_adm.hadm_id
      AND (
        (dd.icd_version = 9 AND dd.icd_code LIKE '43%')
        OR (dd.icd_version = 10 AND dd.icd_code LIKE 'I63%')
      )
    ) THEN 1.0 ELSE 0 END) AS neuro_rate_gen
  FROM first_general_adm
),
combined_stats AS (
  SELECT
    acs.n_acs,
    acs.mean_age_acs,
    NULL AS mean_risk_score_acs,  -- Not available in schema; would require derivation from chartevents
    acs.mort_30d_acs,
    acs.cardiac_rate_acs,
    acs.neuro_rate_acs,
    acs.los_survivors_acs,
    gen.n_gen,
    gen.mean_age_gen,
    NULL AS mean_risk_score_gen,
    gen.mort_30d_gen,
    gen.cardiac_rate_gen,
    gen.neuro_rate_gen,
    gen.los_survivors_gen
  FROM acs_stats acs
  CROSS JOIN general_stats gen
)
SELECT
  n_acs AS acs_cohort_size,
  mean_age_acs AS acs_mean_age,
  mean_risk_score_acs AS acs_mean_risk_score,
  mort_30d_acs AS acs_30d_mortality,
  cardiac_rate_acs AS acs_cardiac_complication_rate,
  neuro_rate_acs AS acs_neurologic_complication_rate,
  los_survivors_acs AS acs_survivor_mean_los_days,
  n_gen AS general_cohort_size,
  mean_age_gen AS general_mean_age,
  mean_risk_score_gen AS general_mean_risk_score,
  mort_30d_gen AS general_30d_mortality,
  cardiac_rate_gen AS general_cardiac_complication_rate,
  neuro_rate_gen AS general_neurologic_complication_rate,
  los_survivors_gen AS general_survivor_mean_los_days,
  (n_acs * 1.0 / n_gen * 100) AS matched_profile_percentile  -- % of age-matched general inpatients with ACS+ICU profile (proxy for rarity/percentile rank)
FROM combined_stats;