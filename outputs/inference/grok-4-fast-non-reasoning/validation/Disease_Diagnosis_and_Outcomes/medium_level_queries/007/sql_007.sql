WITH elixhauser_weights AS (
  -- Simplified Elixhauser van Walraven weights (ICD-10); source: standard literature
  SELECT 'E10-E14' AS code_group, 3 AS weight UNION ALL
  SELECT 'I10', 3 UNION ALL
  SELECT 'J40-J47', -2 UNION ALL
  SELECT 'N18', 6 UNION ALL
  SELECT 'I12-I13', 6 UNION ALL
  SELECT 'K21', 2 UNION ALL
  SELECT 'F20', 0 UNION ALL
  SELECT 'E66', 0 UNION ALL
  SELECT 'E78', 0 UNION ALL
  SELECT 'I95', 3 UNION ALL
  SELECT 'D50', 4 UNION ALL
  SELECT 'C00-D48', -1 UNION ALL
  SELECT 'E05', 0 UNION ALL
  SELECT 'I48', 0 UNION ALL
  SELECT 'K50-K52', 0 UNION ALL
  SELECT 'M05-M06', 0 UNION ALL
  SELECT 'G35', 0 UNION ALL
  SELECT 'I26', 4 UNION ALL
  SELECT 'I80', 1 UNION ALL
  SELECT 'N17-N19', 6 UNION ALL
  SELECT 'F05', 0 UNION ALL
  SELECT 'E55', 0 UNION ALL
  SELECT 'R56', 7 UNION ALL
  SELECT 'N39', 0  -- Add more as needed; this covers major groups
),
comorbidities AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    SUM(COALESCE(ew.weight, 0)) AS elix_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN elixhauser_weights ew 
    ON di.icd_version = '10' 
    AND REGEXP_CONTAINS(di.icd_code, ew.code_group)
  WHERE di.icd_version = '10' AND di.icd_code NOT LIKE 'I50%'
  GROUP BY di.subject_id, di.hadm_id
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8' ELSE '>=8' END AS los_group,
    COALESCE(c.elix_score, 0) AS elix_score,
    CASE 
      WHEN COALESCE(c.elix_score, 0) < 0 THEN 'Low'
      WHEN COALESCE(c.elix_score, 0) <= 4 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t 
        WHERE t.hadm_id = a.hadm_id AND t.careunit LIKE '%ICU%' AND t.eventtype = 'admit'
      ) THEN 'Y' ELSE 'N' 
    END AS icu_yn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN comorbidities c ON a.hadm_id = c.hadm_id
  WHERE p.anchor_age BETWEEN 51 AND 61 
    AND p.gender = 'F'
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id AND d.seq_num = 1 AND d.icd_code LIKE 'I50%'
    )
    AND a.dischtime > a.admittime  -- Valid LOS
),
mv_flag AS (
  SELECT DISTINCT ce.subject_id, ce.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  INNER JOIN cohort c ON ce.subject_id = c.subject_id AND ce.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id
  WHERE (di.label LIKE '%Ventilator%' OR di.abbreviation IN ('VentStart', 'VentEnd'))
    AND ce.value IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime BETWEEN i.intime AND i.outtime
),
vaso_flag AS (
  SELECT DISTINCT ie.subject_id, ie.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.ingredientevents` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  INNER JOIN cohort c ON ie.subject_id = c.subject_id AND ie.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ie.stay_id = i.stay_id
  WHERE di.label IN ('Norepinephrine', 'Epinephrine', 'Dopamine', 'Vasopressin', 'Phenylephrine')
    AND ie.amount > 0
    AND ie.starttime BETWEEN i.intime AND i.outtime
),
rrt_flag AS (
  SELECT DISTINCT pe.subject_id, pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  INNER JOIN cohort c ON pe.subject_id = c.subject_id AND pe.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON pe.stay_id = i.stay_id
  WHERE (di.label LIKE '%Dialysis%' OR di.label LIKE '%CRRT%' OR di.label LIKE '%Hemofiltration%')
    AND pe.value IS NOT NULL
    AND pe.starttime BETWEEN i.intime AND i.outtime
),
stratified_outcomes AS (
  SELECT 
    co.*,
    CASE WHEN mf.subject_id IS NOT NULL THEN 1 ELSE 0 END AS mv_yn,
    CASE WHEN vf.subject_id IS NOT NULL THEN 1 ELSE 0 END AS vaso_yn,
    CASE WHEN rf.subject_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_yn
  FROM cohort co
  LEFT JOIN mv_flag mf ON co.subject_id = mf.subject_id AND co.hadm_id = mf.hadm_id
  LEFT JOIN vaso_flag vf ON co.subject_id = vf.subject_id AND co.hadm_id = vf.hadm_id
  LEFT JOIN rrt_flag rf ON co.subject_id = rf.subject_id AND co.hadm_id = rf.hadm_id
)
SELECT 
  icu_yn,
  los_group,
  comorbidity_burden,
  -- Mortality rate (%)
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_pct,
  -- Absolute difference (ICU - noICU)
  ROUND(
    AVG(CASE WHEN icu_yn = 'Y' THEN hospital_expire_flag ELSE 0 END) * 100 -
    AVG(CASE WHEN icu_yn = 'N' THEN hospital_expire_flag ELSE 0 END) * 100, 2
  ) AS abs_diff_mortality_pct,
  -- Relative difference ((ICU - noICU)/noICU * 100)
  ROUND(
    (AVG(CASE WHEN icu_yn = 'Y' THEN hospital_expire_flag ELSE 0 END) -
     AVG(CASE WHEN icu_yn = 'N' THEN hospital_expire_flag ELSE 0 END)) /
    NULLIF(AVG(CASE WHEN icu_yn = 'N' THEN hospital_expire_flag ELSE 0 END), 0) * 100, 2
  ) AS rel_diff_mortality_pct,
  -- Prevalences (only for ICU)
  ROUND(AVG(CASE WHEN icu_yn = 'Y' AND mv_yn = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mv_prevalence_pct,
  ROUND(AVG(CASE WHEN icu_yn = 'Y' AND vaso_yn = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS vaso_prevalence_pct,
  ROUND(AVG(CASE WHEN icu_yn = 'Y' AND rrt_yn = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS rrt_prevalence_pct,
  COUNT(*) AS n_patients
FROM stratified_outcomes
GROUP BY icu_yn, los_group, comorbidity_burden
ORDER BY los_group, comorbidity_burden, icu_yn;