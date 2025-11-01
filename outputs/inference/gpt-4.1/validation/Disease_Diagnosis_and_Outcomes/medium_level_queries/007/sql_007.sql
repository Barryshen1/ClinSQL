WITH heart_failure_icds AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
),
hf_admissions AS (
  -- Female, age 51-61, heart failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN heart_failure_icds hf
    ON diag.icd_code = hf.icd_code AND diag.icd_version = hf.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 51 AND 61
),
comorbidity_counts AS (
  -- Count unique non-HF ICD codes per admission
  SELECT
    hadm_id,
    COUNT(DISTINCT CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM heart_failure_icds hf
        WHERE diag.icd_code = hf.icd_code AND diag.icd_version = hf.icd_version
      ) THEN diag.icd_code
      ELSE NULL
    END) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  GROUP BY hadm_id
),
icu_flags AS (
  -- Flag admissions with ICU stay
  SELECT DISTINCT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
los_groups AS (
  SELECT
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) < 8 THEN '<8'
      ELSE '>=8'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
comorbidity_burden AS (
  SELECT
    hadm_id,
    CASE
      WHEN comorbidity_count <= 1 THEN 'low'
      WHEN comorbidity_count BETWEEN 2 AND 4 THEN 'medium'
      ELSE 'high'
    END AS burden
  FROM comorbidity_counts
),
mv_admissions AS (
  -- MV: procedureevents with ventilation, or chartevents with ventilation
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE LOWER(ordercategorydescription) LIKE '%ventilation%'
     OR LOWER(ordercategoryname) LIKE '%ventilation%'
     OR LOWER(ordercategorydescription) LIKE '%mechanical ventilation%'
),
vaso_admissions AS (
  -- Vasopressors: inputevents/ingredientevents with common vaso drugs via d_items.label
  SELECT DISTINCT inp.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` inp
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON inp.itemid = di.itemid
  WHERE LOWER(di.label) IN (
    'norepinephrine', 'epinephrine', 'vasopressin', 'dopamine', 'phenylephrine'
  )
  UNION DISTINCT
  SELECT DISTINCT ing.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ing.itemid = di.itemid
  WHERE LOWER(di.label) IN (
    'norepinephrine', 'epinephrine', 'vasopressin', 'dopamine', 'phenylephrine'
  )
),
rrt_admissions AS (
  -- RRT: procedureevents/inputevents with dialysis/CRRT via d_items.label/category
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%rrt%'
     OR LOWER(di.label) LIKE '%renal replacement%'
     OR LOWER(di.label) LIKE '%crrt%'
     OR LOWER(di.category) LIKE '%dialysis%'
     OR LOWER(di.category) LIKE '%rrt%'
     OR LOWER(di.category) LIKE '%renal replacement%'
     OR LOWER(di.category) LIKE '%crrt%'
  UNION DISTINCT
  SELECT DISTINCT inp.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` inp
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON inp.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%rrt%'
     OR LOWER(di.label) LIKE '%renal replacement%'
     OR LOWER(di.label) LIKE '%crrt%'
     OR LOWER(di.category) LIKE '%dialysis%'
     OR LOWER(di.category) LIKE '%rrt%'
     OR LOWER(di.category) LIKE '%renal replacement%'
     OR LOWER(di.category) LIKE '%crrt%'
  UNION DISTINCT
  SELECT DISTINCT ing.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ing.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%rrt%'
     OR LOWER(di.label) LIKE '%renal replacement%'
     OR LOWER(di.label) LIKE '%crrt%'
     OR LOWER(di.category) LIKE '%dialysis%'
     OR LOWER(di.category) LIKE '%rrt%'
     OR LOWER(di.category) LIKE '%renal replacement%'
     OR LOWER(di.category) LIKE '%crrt%'
),
final_cohort AS (
  SELECT
    hf.subject_id,
    hf.hadm_id,
    COALESCE(icu.icu_flag, 0) AS icu_flag,
    los.los_group,
    cb.burden,
    hf.hospital_expire_flag,
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mv_flag,
    CASE WHEN vaso.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vaso_flag,
    CASE WHEN rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_flag
  FROM hf_admissions hf
  LEFT JOIN icu_flags icu ON hf.hadm_id = icu.hadm_id
  LEFT JOIN los_groups los ON hf.hadm_id = los.hadm_id
  LEFT JOIN comorbidity_burden cb ON hf.hadm_id = cb.hadm_id
  LEFT JOIN mv_admissions mv ON hf.hadm_id = mv.hadm_id
  LEFT JOIN vaso_admissions vaso ON hf.hadm_id = vaso.hadm_id
  LEFT JOIN rrt_admissions rrt ON hf.hadm_id = rrt.hadm_id
)
-- Aggregate and compare ICU vs no ICU
SELECT
  icu_flag,
  los_group,
  burden,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate,
  SUM(mv_flag) AS n_mv,
  SAFE_DIVIDE(SUM(mv_flag), COUNT(*)) AS mv_prevalence,
  SUM(vaso_flag) AS n_vaso,
  SAFE_DIVIDE(SUM(vaso_flag), COUNT(*)) AS vaso_prevalence,
  SUM(rrt_flag) AS n_rrt,
  SAFE_DIVIDE(SUM(rrt_flag), COUNT(*)) AS rrt_prevalence
FROM final_cohort
GROUP BY icu_flag, los_group, burden
ORDER BY icu_flag DESC, los_group, burden;