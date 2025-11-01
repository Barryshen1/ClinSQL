WITH comorbidity_quan AS (
  SELECT * FROM UNNEST([
    STRUCT('410' AS icd_code, 9 AS icd_version, 'MI' AS comorbidity),
    STRUCT('4100', 9, 'MI'), STRUCT('41000', 9, 'MI'), STRUCT('41001', 9, 'MI'), 
    -- ... (All other ICD-9 and ICD-10 codes for Charlson categories) ...
    STRUCT('N18', 10, 'Renal'), STRUCT('N19', 10, 'Renal'), STRUCT('N250', 10, 'Renal'),
    STRUCT('I120', 10, 'Renal'), STRUCT('I131', 10, 'Renal'), STRUCT('N032', 10, 'Renal'),
    STRUCT('N033', 10, 'Renal'), STRUCT('N034', 10, 'Renal'), STRUCT('N035', 10, 'Renal'),
    STRUCT('N036', 10, 'Renal'), STRUCT('N037', 10, 'Renal'), STRUCT('N052', 10, 'Renal'),
    STRUCT('N053', 10, 'Renal'), STRUCT('N054', 10, 'Renal'), STRUCT('N055', 10, 'Renal'),
    STRUCT('N056', 10, 'Renal'), STRUCT('N057', 10, 'Renal'), STRUCT('N250', 10, 'Renal'),
    STRUCT('Z490', 10, 'Renal'), STRUCT('Z491', 10, 'Renal'), STRUCT('Z492', 10, 'Renal'),
    STRUCT('Z940', 10, 'Renal'), STRUCT('Z992', 10, 'Renal')
  ])
),
charlson_components AS (
  SELECT 
    diag.hadm_id,
    cm.comorbidity,
    MAX(CASE 
        WHEN cm.comorbidity = 'MI' THEN 1
        WHEN cm.comorbidity = 'CHF' THEN 1
        WHEN cm.comorbidity = 'PVD' THEN 1
        WHEN cm.comorbidity = 'Stroke' THEN 1
        WHEN cm.comorbidity = 'Dementia' THEN 1
        WHEN cm.comorbidity = 'Pulmonary' THEN 1
        WHEN cm.comorbidity = 'Rheumatic' THEN 1
        WHEN cm.comorbidity = 'PUD' THEN 1
        WHEN cm.comorbidity = 'LiverMild' THEN 1
        WHEN cm.comorbidity = 'DM' THEN 1
        WHEN cm.comorbidity = 'DMcx' THEN 2
        WHEN cm.comorbidity = 'Paralysis' THEN 2
        WHEN cm.comorbidity = 'Renal' THEN 2
        WHEN cm.comorbidity = 'Cancer' THEN 2
        WHEN cm.comorbidity = 'LiverSevere' THEN 3
        WHEN cm.comorbidity = 'Mets' THEN 6
        WHEN cm.comorbidity = 'HIV' THEN 6
    END) AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN comorbidity_quan cm
    ON diag.icd_code = cm.icd_code 
    AND diag.icd_version = cm.icd_version
  GROUP BY diag.hadm_id, cm.comorbidity
),
charlson_per_admission AS (
  SELECT 
    hadm_id,
    SUM(weight) AS charlson_score,
    MAX(CASE WHEN comorbidity IN ('DM', 'DMcx') THEN 1 ELSE 0 END) AS diabetes_flag,
    MAX(CASE WHEN comorbidity = 'Renal' THEN 1 ELSE 0 END) AS ckd_flag
  FROM charlson_components
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '998%') 
        OR (icd_version = 10 AND icd_code LIKE 'T81%')
    )
),
cohort_with_charlson AS (
  SELECT 
    c.*,
    COALESCE(cpa.charlson_score, 0) AS charlson_score,
    COALESCE(cpa.diabetes_flag, 0) AS diabetes_flag,
    COALESCE(cpa.ckd_flag, 0) AS ckd_flag
  FROM cohort c
  LEFT JOIN charlson_per_admission cpa
    ON c.hadm_id = cpa.hadm_id
  WHERE c.los_days >= 1
),
cohort_with_strata AS (
  SELECT 
    *,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = c.hadm_id
      ) THEN 'ICU' 
      ELSE 'non-ICU' 
    END AS icu_flag,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
    END AS los_group,
    CASE 
      WHEN charlson_score <= 1 THEN '0-1'
      WHEN charlson_score = 2 THEN '2'
      WHEN charlson_score >= 3 THEN '>=3'
    END AS charlson_group
  FROM cohort_with_charlson c
  WHERE age_at_admission BETWEEN 51 AND 61
)
SELECT 
  icu_flag,
  los_group,
  charlson_group,
  COUNT(*) AS num_patients,
  SUM(hospital_expire_flag) AS num_deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percentage,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  ROUND(SUM(diabetes_flag) * 100.0 / COUNT(*), 2) AS diabetes_prevalence,
  ROUND(SUM(ckd_flag) * 100.0 / COUNT(*), 2) AS ckd_prevalence
FROM cohort_with_strata
GROUP BY icu_flag, los_group, charlson_group
ORDER BY icu_flag, los_group, charlson_group;