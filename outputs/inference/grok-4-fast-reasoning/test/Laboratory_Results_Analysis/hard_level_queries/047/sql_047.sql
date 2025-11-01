WITH patient_ages AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
ards_hadms AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.age, pa.admittime, pa.dischtime, pa.hospital_expire_flag
  FROM patient_ages pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.subject_id = d.subject_id AND pa.hadm_id = d.hadm_id
  WHERE pa.gender = 'M'
    AND pa.age BETWEEN 71 AND 81
    AND d.icd_code = 'J80'
    AND d.icd_version = 10
),
first_icu_stays AS (
  SELECT 
    ah.subject_id, 
    ah.hadm_id, 
    i.stay_id, 
    i.intime,
    ROW_NUMBER() OVER (PARTITION BY ah.hadm_id ORDER BY i.intime) AS rn
  FROM ards_hadms ah
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ah.subject_id = i.subject_id AND ah.hadm_id = i.hadm_id
),
ards_cohort AS (
  SELECT ac.subject_id, ac.hadm_id, ac.stay_id, ac.intime
  FROM first_icu_stays ac
  WHERE ac.rn = 1
),
instability_scores AS (
  SELECT 
    ac.stay_id,
    ac.hadm_id,
    COUNT(*) AS instability_score
  FROM ards_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON ac.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE c.charttime BETWEEN ac.intime AND TIMESTAMP_ADD(ac.intime, INTERVAL 72 HOUR)
    AND c.warning IS NOT NULL
    AND di.category = 'Routine Vital Signs'
  GROUP BY ac.stay_id, ac.hadm_id
),
scores_with_p90 AS (
  SELECT 
    hadm_id,
    instability_score,
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90
  FROM instability_scores
),
high_instability_hadms AS (
  SELECT DISTINCT hadm_id
  FROM scores_with_p90
  WHERE instability_score >= p90
),
high_subgroup_stats AS (
  SELECT 
    AVG(ah.hospital_expire_flag) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(ah.dischtime, ah.admittime, HOUR) / 24.0) AS mean_los_days
  FROM high_instability_hadms hih
  INNER JOIN ards_hadms ah ON hih.hadm_id = ah.hadm_id
),
p90_value AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_threshold
  FROM instability_scores
),
general_hadms AS (
  SELECT hadm_id, admittime, dischtime
  FROM patient_ages
  WHERE gender = 'M' AND age BETWEEN 71 AND 81
),
-- Critical lab rates for high ARDS subgroup
high_creatinine AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.valuenum > 2.0 AND l.valuenum IS NOT NULL THEN ah.hadm_id END) * 100.0 / COUNT(DISTINCT ah.hadm_id) AS creatinine_critical_rate_pct
  FROM high_instability_hadms hih
  INNER JOIN ards_hadms ah ON hih.hadm_id = ah.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ah.hadm_id = l.hadm_id
    AND l.itemid = 50912  -- Creatinine
    AND l.charttime BETWEEN ah.admittime AND ah.dischtime
),
high_bilirubin AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.valuenum > 2.0 AND l.valuenum IS NOT NULL THEN ah.hadm_id END) * 100.0 / COUNT(DISTINCT ah.hadm_id) AS bilirubin_critical_rate_pct
  FROM high_instability_hadms hih
  INNER JOIN ards_hadms ah ON hih.hadm_id = ah.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ah.hadm_id = l.hadm_id
    AND l.itemid = 50885  -- Total Bilirubin
    AND l.charttime BETWEEN ah.admittime AND ah.dischtime
),
high_platelets AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.valuenum < 100 AND l.valuenum IS NOT NULL THEN ah.hadm_id END) * 100.0 / COUNT(DISTINCT ah.hadm_id) AS platelets_critical_rate_pct
  FROM high_instability_hadms hih
  INNER JOIN ards_hadms ah ON hih.hadm_id = ah.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ah.hadm_id = l.hadm_id
    AND l.itemid = 51265  -- Platelets
    AND l.charttime BETWEEN ah.admittime AND ah.dischtime
),
high_sodium AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN (l.valuenum < 130 OR l.valuenum > 155) AND l.valuenum IS NOT NULL THEN ah.hadm_id END) * 100.0 / COUNT(DISTINCT ah.hadm_id) AS sodium_critical_rate_pct
  FROM high_instability_hadms hih
  INNER JOIN ards_hadms ah ON hih.hadm_id = ah.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ah.hadm_id = l.hadm_id
    AND l.itemid = 50983  -- Sodium
    AND l.charttime BETWEEN ah.admittime AND ah.dischtime
),
high_potassium AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN (l.valuenum < 2.5 OR l.valuenum > 6.0) AND l.valuenum IS NOT NULL THEN ah.hadm_id END) * 100.0 / COUNT(DISTINCT ah.hadm_id) AS potassium_critical_rate_pct
  FROM high_instability_hadms hih
  INNER JOIN ards_hadms ah ON hih.hadm_id = ah.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ah.hadm_id = l.hadm_id
    AND l.itemid = 50971  -- Potassium
    AND l.charttime BETWEEN ah.admittime AND ah.dischtime
),
-- Critical lab rates for general inpatients
gen_creatinine AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.valuenum > 2.0 AND l.valuenum IS NOT NULL THEN gh.hadm_id END) * 100.0 / COUNT(DISTINCT gh.hadm_id) AS creatinine_critical_rate_pct
  FROM general_hadms gh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON gh.hadm_id = l.hadm_id
    AND l.itemid = 50912
    AND l.charttime BETWEEN gh.admittime AND gh.dischtime
),
gen_bilirubin AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.valuenum > 2.0 AND l.valuenum IS NOT NULL THEN gh.hadm_id END) * 100.0 / COUNT(DISTINCT gh.hadm_id) AS bilirubin_critical_rate_pct
  FROM general_hadms gh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON gh.hadm_id = l.hadm_id
    AND l.itemid = 50885
    AND l.charttime BETWEEN gh.admittime AND gh.dischtime
),
gen_platelets AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.valuenum < 100 AND l.valuenum IS NOT NULL THEN gh.hadm_id END) * 100.0 / COUNT(DISTINCT gh.hadm_id) AS platelets_critical_rate_pct
  FROM general_hadms gh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON gh.hadm_id = l.hadm_id
    AND l.itemid = 51265
    AND l.charttime BETWEEN gh.admittime AND gh.dischtime
),
gen_sodium AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN (l.valuenum < 130 OR l.valuenum > 155) AND l.valuenum IS NOT NULL THEN gh.hadm_id END) * 100.0 / COUNT(DISTINCT gh.hadm_id) AS sodium_critical_rate_pct
  FROM general_hadms gh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON gh.hadm_id = l.hadm_id
    AND l.itemid = 50983
    AND l.charttime BETWEEN gh.admittime AND gh.dischtime
),
gen_potassium AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN (l.valuenum < 2.5 OR l.valuenum > 6.0) AND l.valuenum IS NOT NULL THEN gh.hadm_id END) * 100.0 / COUNT(DISTINCT gh.hadm_id) AS potassium_critical_rate_pct
  FROM general_hadms gh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON gh.hadm_id = l.hadm_id
    AND l.itemid = 50971
    AND l.charttime BETWEEN gh.admittime AND gh.dischtime
)
SELECT 
  p90.p90_threshold,
  hs.mortality_rate,
  hs.mean_los_days,
  hc.creatinine_critical_rate_pct AS high_ards_creatinine_pct,
  gc.creatinine_critical_rate_pct AS general_creatinine_pct,
  hb.bilirubin_critical_rate_pct AS high_ards_bilirubin_pct,
  gb.bilirubin_critical_rate_pct AS general_bilirubin_pct,
  hp.platelets_critical_rate_pct AS high_ards_platelets_pct,
  gp.platelets_critical_rate_pct AS general_platelets_pct,
  hna.sodium_critical_rate_pct AS high_ards_sodium_pct,
  gna.sodium_critical_rate_pct AS general_sodium_pct,
  hpk.potassium_critical_rate_pct AS high_ards_potassium_pct,
  gpk.potassium_critical_rate_pct AS general_potassium_pct
FROM p90_value p90
CROSS JOIN high_subgroup_stats hs
CROSS JOIN high_creatinine hc
CROSS JOIN gen_creatinine gc
CROSS JOIN high_bilirubin hb
CROSS JOIN gen_bilirubin gb
CROSS JOIN high_platelets hp
CROSS JOIN gen_platelets gp
CROSS JOIN high_sodium hna
CROSS JOIN gen_sodium gna
CROSS JOIN high_potassium hpk
CROSS JOIN gen_potassium gpk;