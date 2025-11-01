WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.dod, 
    p.anchor_age, 
    p.anchor_year,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age,
    CASE 
      WHEN a.deathtime IS NOT NULL 
        AND a.deathtime <= TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY) THEN 1
      WHEN p.dod IS NOT NULL 
        AND a.hospital_expire_flag = 0 
        AND DATE(p.dod) <= DATE(TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY)) THEN 1
      ELSE 0 
    END AS died_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
),
num_comorb AS (
  SELECT 
    di.subject_id, 
    di.hadm_id, 
    COUNT(DISTINCT di.icd_code) AS num_comorb
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num > 1
  GROUP BY di.subject_id, di.hadm_id
),
pe_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '415.1%')
     OR (icd_version = 10 AND icd_code LIKE 'I26%')
),
pe_cohort AS (
  SELECT 
    c.*,
    COALESCE(nc.num_comorb, 0) AS num_comorb
  FROM cohort c
  INNER JOIN pe_hadms pe ON c.hadm_id = pe.hadm_id
  LEFT JOIN num_comorb nc ON c.hadm_id = nc.hadm_id
),
median_comorb AS (
  SELECT APPROX_QUANTILES(num_comorb, 100)[OFFSET(50)] AS median_num
  FROM pe_cohort
),
target_group AS (
  SELECT pc.*
  FROM pe_cohort pc
  CROSS JOIN median_comorb m
  WHERE pc.num_comorb > m.median_num
),
general_group AS (
  SELECT 
    c.*,
    COALESCE(nc.num_comorb, 0) AS num_comorb
  FROM cohort c
  LEFT JOIN num_comorb nc ON c.hadm_id = nc.hadm_id
),
has_cardio_comp AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (
    (di.icd_version = 10 AND (
      di.icd_code LIKE 'I21%' OR 
      di.icd_code LIKE 'I22%' OR 
      di.icd_code LIKE 'I46%'
    ))
    OR 
    (di.icd_version = 9 AND (
      di.icd_code LIKE '410%' OR 
      di.icd_code LIKE '411%' OR 
      di.icd_code LIKE '427.5%'
    ))
  )
    AND NOT (
      (di.icd_version = 9 AND di.icd_code LIKE '415.1%')
      OR 
      (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
    )
),
has_neuro_comp AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (
    (di.icd_version = 10 AND (
      di.icd_code LIKE 'I63%' OR 
      di.icd_code LIKE 'I61%' OR 
      di.icd_code LIKE 'I62%' OR 
      di.icd_code LIKE 'G45%'
    ))
    OR 
    (di.icd_version = 9 AND (
      di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%' OR
      di.icd_code LIKE '433%' OR di.icd_code LIKE '434%' OR
      di.icd_code LIKE '436%' OR di.icd_code LIKE '437%' OR di.icd_code LIKE '438%'
    ))
  )
),
target_stats AS (
  SELECT 
    AVG(num_comorb) AS mean_comorb,
    AVG(died_30d) AS mort_30d,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN DATE_DIFF(dischtime, admittime, DAY) END) AS mean_los,
    COUNTIF(cc.hadm_id IS NOT NULL) * 1.0 / COUNT(*) AS cardio_rate,
    COUNTIF(nc.hadm_id IS NOT NULL) * 1.0 / COUNT(*) AS neuro_rate
  FROM target_group tg
  LEFT JOIN has_cardio_comp cc ON tg.hadm_id = cc.hadm_id
  LEFT JOIN has_neuro_comp nc ON tg.hadm_id = nc.hadm_id
),
general_stats AS (
  SELECT 
    AVG(CASE WHEN hospital_expire_flag = 0 THEN DATE_DIFF(dischtime, admittime, DAY) END) AS mean_los_gen,
    COUNTIF(cc.hadm_id IS NOT NULL) * 1.0 / COUNT(*) AS cardio_rate_gen,
    COUNTIF(nc.hadm_id IS NOT NULL) * 1.0 / COUNT(*) AS neuro_rate_gen
  FROM general_group g
  LEFT JOIN has_cardio_comp cc ON g.hadm_id = cc.hadm_id
  LEFT JOIN has_neuro_comp nc ON g.hadm_id = nc.hadm_id
)
SELECT 
  ts.mean_comorb AS target_mean_comorbidity_score,
  ts.mort_30d AS target_30day_mortality,
  ts.cardio_rate AS target_cardio_complication_rate,
  ts.neuro_rate AS target_neurologic_complication_rate,
  ts.mean_los AS target_survivor_los,
  gs.cardio_rate_gen AS general_cardio_complication_rate,
  gs.neuro_rate_gen AS general_neurologic_complication_rate,
  gs.mean_los_gen AS general_survivor_los,
  (SELECT COUNTIF(gg.num_comorb < ts.mean_comorb) * 1.0 / COUNT(*) 
   FROM general_group gg) AS matched_profile_percentile_vs_controls
FROM target_stats ts
CROSS JOIN general_stats gs;