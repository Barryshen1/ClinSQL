WITH diag_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'T8%'
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN diag_hadm dh 
    ON a.subject_id = dh.subject_id AND a.hadm_id = dh.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 71 AND 81
),
mv_procs AS (
  SELECT DISTINCT pi.subject_id, pi.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ventilation%' 
     OR LOWER(dip.long_title) LIKE '%respirator%'
),
rrt_procs AS (
  SELECT DISTINCT pi.subject_id, pi.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%dialysis%' 
     OR LOWER(dip.long_title) LIKE '%filtration%' 
     OR LOWER(dip.long_title) LIKE '%replacement%'
),
vaso_presc AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%norepinephrine%' 
     OR LOWER(drug) LIKE '%noradrenaline%' 
     OR LOWER(drug) LIKE '%dopamine%' 
     OR LOWER(drug) LIKE '%epinephrine%' 
     OR LOWER(drug) LIKE '%adrenaline%' 
     OR LOWER(drug) LIKE '%phenylephrine%' 
     OR LOWER(drug) LIKE '%vasopressin%' 
     OR LOWER(drug) LIKE '%dobutamine%'
),
icu_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_full AS (
  SELECT 
    c.*,
    CASE WHEN i.subject_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag,
    CASE WHEN mv.subject_id IS NOT NULL THEN 1 ELSE 0 END AS had_mv,
    CASE WHEN rrt.subject_id IS NOT NULL THEN 1 ELSE 0 END AS had_rrt,
    CASE WHEN vp.subject_id IS NOT NULL THEN 1 ELSE 0 END AS had_vaso
  FROM cohort c
  LEFT JOIN icu_hadm i 
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  LEFT JOIN mv_procs mv 
    ON c.subject_id = mv.subject_id AND c.hadm_id = mv.hadm_id
  LEFT JOIN rrt_procs rrt 
    ON c.subject_id = rrt.subject_id AND c.hadm_id = rrt.hadm_id
  LEFT JOIN vaso_presc vp 
    ON c.subject_id = vp.subject_id AND c.hadm_id = vp.hadm_id
),
cohort_quart AS (
  SELECT 
    *,
    NTILE(4) OVER (PARTITION BY icu_flag ORDER BY los_days ASC) AS quartile
  FROM cohort_full
),
summary AS (
  SELECT 
    icu_flag,
    quartile,
    COUNT(*) AS n,
    SUM(CAST(hospital_expire_flag AS INT64)) AS deaths,
    ROUND(SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*), 2) AS mortality_pct,
    ROUND(AVG(CAST(had_mv AS FLOAT64)) * 100, 2) AS pct_mv,
    ROUND(AVG(CAST(had_vaso AS FLOAT64)) * 100, 2) AS pct_vaso,
    ROUND(AVG(CAST(had_rrt AS FLOAT64)) * 100, 2) AS pct_rrt
  FROM cohort_quart
  GROUP BY icu_flag, quartile
),
q1_mort AS (
  SELECT icu_flag, mortality_pct AS q1_mortality
  FROM summary
  WHERE quartile = 1
)
SELECT 
  s.icu_flag,
  CASE WHEN s.icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS group_name,
  s.quartile,
  s.n,
  s.deaths,
  s.mortality_pct,
  CASE 
    WHEN s.quartile = 1 THEN 1.0 
    ELSE ROUND(s.mortality_pct / q.q1_mortality, 2) 
  END AS relative_mortality,
  s.pct_mv,
  s.pct_vaso,
  s.pct_rrt
FROM summary s
LEFT JOIN q1_mort q 
  ON s.icu_flag = q.icu_flag
ORDER BY s.icu_flag, s.quartile;