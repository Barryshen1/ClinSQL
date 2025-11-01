WITH patients_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_quartiles AS (
  SELECT 
    APPROX_QUANTILES(los_days, 4) AS quartiles
  FROM patients_admissions
),
expanded_quartiles AS (
  SELECT 
    quartiles[OFFSET(0)] AS q0,
    quartiles[OFFSET(1)] AS q1,
    quartiles[OFFSET(2)] AS q2,
    quartiles[OFFSET(3)] AS q3,
    quartiles[OFFSET(4)] AS q4
  FROM los_quartiles
),
cohort_with_quartiles AS (
  SELECT 
    pa.*,
    CASE 
      WHEN pa.los_days <= e.q1 THEN 1
      WHEN pa.los_days <= e.q2 THEN 2
      WHEN pa.los_days <= e.q3 THEN 3
      ELSE 4
    END AS los_quartile
  FROM patients_admissions pa, expanded_quartiles e
),
icu_flags AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
mech_vent_flags AS (
  SELECT DISTINCT hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_code IN ('96.7','96.70','96.71','96.72','96.73','96.74','96.75','96.76','96.77','96.78','96.79')
    AND icd_version = 9
),
rrt_flags AS (
  SELECT DISTINCT hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_code IN ('39.95','39.94','39.93','54.99')
    AND icd_version = 9
),
vasopressor_flags AS (
  SELECT DISTINCT hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug LIKE '%norepinephrine%' OR 
        drug LIKE '%epinephrine%' OR 
        drug LIKE '%dopamine%' OR 
        drug LIKE '%vasopressin%' OR 
        drug LIKE '%phenylephrine%' OR 
        drug LIKE '%dobutamine%' OR 
        drug LIKE '%isoproterenol%' OR 
        drug LIKE '%angiotensin%' OR 
        drug LIKE '%metaraminol%' OR 
        drug LIKE '%midodrine%' OR 
        drug LIKE '%tyramine%' OR 
        drug LIKE '%oxytocin%'
),
combined AS (
  SELECT 
    c.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu,
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent_flag,
    CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressor_flag,
    CASE WHEN rr.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_flag
  FROM cohort_with_quartiles c
  LEFT JOIN icu_flags i ON c.hadm_id = i.hadm_id
  LEFT JOIN mech_vent_flags mv ON c.hadm_id = mv.hadm_id
  LEFT JOIN vasopressor_flags vp ON c.hadm_id = vp.hadm_id
  LEFT JOIN rrt_flags rr ON c.hadm_id = rr.hadm_id
),
aggregated AS (
  SELECT 
    icu,
    los_quartile,
    COUNT(*) AS num_admissions,
    SUM(hospital_expire_flag) AS num_deaths,
    SUM(mech_vent_flag) AS num_mech_vent,
    SUM(vasopressor_flag) AS num_vasopressors,
    SUM(rrt_flag) AS num_rrt
  FROM combined
  GROUP BY icu, los_quartile
),
q1_mortality AS (
  SELECT 
    icu,
    num_deaths * 1.0 / num_admissions AS q1_mort
  FROM aggregated
  WHERE los_quartile = 1
)
SELECT 
  a.icu,
  a.los_quartile,
  a.num_admissions,
  a.num_deaths,
  a.num_deaths * 1.0 / a.num_admissions AS abs_mortality,
  CASE 
    WHEN a.los_quartile = 1 THEN 0.0
    ELSE (a.num_deaths * 1.0 / a.num_admissions - q1.q1_mort) / q1.q1_mort 
  END AS rel_mortality,
  a.num_mech_vent * 1.0 / a.num_admissions AS pct_mech_vent,
  a.num_vasopressors * 1.0 / a.num_admissions AS pct_vasopressors,
  a.num_rrt * 1.0 / a.num_admissions AS pct_rrt
FROM aggregated a
LEFT JOIN q1_mortality q1 ON a.icu = q1.icu
ORDER BY a.icu, a.los_quartile;