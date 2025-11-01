WITH stroke_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE 
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'I63%' OR di.icd_code LIKE '433%' OR di.icd_code LIKE '434%'))
            OR (di.icd_version = 9 AND (di.icd_code LIKE '433%' OR di.icd_code LIKE '434%'))
          THEN 1 ELSE 0 END) AS ischemic_flag,
    MAX(CASE 
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%'))
            OR (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%'))
          THEN 1 ELSE 0 END) AS hemorrhagic_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
comorbidity_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE 
          WHEN (di.icd_version = 10 AND di.icd_code LIKE 'N18%')
            OR (di.icd_version = 9 AND di.icd_code LIKE '585%')
          THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE 
          WHEN (di.icd_version = 10 AND di.icd_code BETWEEN 'E10' AND 'E14')
            OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
          THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    sf.ischemic_flag,
    sf.hemorrhagic_flag,
    cf.ckd_flag,
    cf.diabetes_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN stroke_flags sf
    ON p.subject_id = sf.subject_id AND a.hadm_id = sf.hadm_id
  JOIN comorbidity_flags cf
    ON p.subject_id = cf.subject_id AND a.hadm_id = cf.hadm_id
  WHERE gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
    AND (sf.ischemic_flag = 1 OR sf.hemorrhagic_flag = 1)
    AND NOT (sf.ischemic_flag = 1 AND sf.hemorrhagic_flag = 1)
),
with_comorbidity_count AS (
  SELECT
    *,
    (COALESCE(ckd_flag,0) + COALESCE(diabetes_flag,0)) AS comorb_count
  FROM cohort
),
with_tertile AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorb_count) AS comorb_tertile,
    CASE WHEN los_days < 8 THEN '<8 days' ELSE '≥8 days' END AS los_category
  FROM with_comorbidity_count
),
final_summary AS (
  SELECT
    CASE WHEN ischemic_flag = 1 THEN 'Ischemic' ELSE 'Hemorrhagic' END AS stroke_type,
    los_category,
    comorb_tertile,
    COUNT(*) AS n_admissions,
    100.0*SUM(hospital_expire_flag)/COUNT(*) AS mortality_percent,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    100.0*SUM(ckd_flag)/COUNT(*) AS ckd_prevalence_percent,
    100.0*SUM(diabetes_flag)/COUNT(*) AS diabetes_prevalence_percent
  FROM with_tertile
  GROUP BY stroke_type, los_category, comorb_tertile
)
SELECT * 
FROM final_summary
ORDER BY stroke_type, los_category, comorb_tertile;