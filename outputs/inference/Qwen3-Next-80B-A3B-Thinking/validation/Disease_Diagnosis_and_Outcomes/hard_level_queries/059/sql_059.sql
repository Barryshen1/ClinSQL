WITH dka_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND di.long_title LIKE '%ketoacidosis%'
),
dka_icustays AS (
  SELECT 
    dc.subject_id,
    dc.hadm_id,
    i.stay_id
  FROM dka_cohort dc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON dc.subject_id = i.subject_id AND dc.hadm_id = i.hadm_id
),
dka_sofa AS (
  SELECT 
    dka_icustays.subject_id,
    dka_icustays.hadm_id,
    MAX(c.valuenum) AS sofa_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN dka_icustays ON c.stay_id = dka_icustays.stay_id
  WHERE c.itemid = 223900
  GROUP BY dka_icustays.subject_id, dka_icustays.hadm_id
),
dka_stats AS (
  SELECT 
    AVG(dka_sofa.sofa_value) AS mean_sofa,
    SUM(CASE WHEN dka_cohort.dod IS NOT NULL AND dka_cohort.dod <= DATE(dka_cohort.admittime) + INTERVAL 30 DAY THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS mortality_30d
  FROM dka_cohort
  LEFT JOIN dka_sofa ON dka_cohort.subject_id = dka_sofa.subject_id AND dka_cohort.hadm_id = dka_sofa.hadm_id
),
general_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
general_aki AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN di.long_title LIKE '%acute kidney injury%' OR di.long_title LIKE '%acute renal failure%' THEN gc.hadm_id END) * 1.0 / COUNT(DISTINCT gc.hadm_id) AS aki_rate
  FROM general_cohort gc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON gc.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
),
general_ards AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN di.long_title LIKE '%acute respiratory distress syndrome%' THEN gc.hadm_id END) * 1.0 / COUNT(DISTINCT gc.hadm_id) AS ards_rate
  FROM general_cohort gc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON gc.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
),
general_survivor_los AS (
  SELECT 
    AVG(CASE WHEN hospital_expire_flag = 0 THEN DATE_DIFF(dischtime, admittime, DAY) END) AS survivor_los
  FROM general_cohort
),
general_icustays AS (
  SELECT 
    gc.subject_id,
    gc.hadm_id,
    i.stay_id
  FROM general_cohort gc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON gc.subject_id = i.subject_id AND gc.hadm_id = i.hadm_id
),
general_sofa AS (
  SELECT 
    c.valuenum AS sofa_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN general_icustays ON c.stay_id = general_icustays.stay_id
  WHERE c.itemid = 223900
),
percentile_calc AS (
  SELECT 
    COUNTIF(sofa_value <= (SELECT mean_sofa FROM dka_stats)) * 100.0 / COUNT(*) AS percentile
  FROM general_sofa
)
SELECT 
  dka_stats.mean_sofa,
  dka_stats.mortality_30d,
  general_aki.aki_rate,
  general_ards.ards_rate,
  general_survivor_los.survivor_los,
  percentile_calc.percentile
FROM dka_stats
CROSS JOIN general_aki
CROSS JOIN general_ards
CROSS JOIN general_survivor_los
CROSS JOIN percentile_calc;