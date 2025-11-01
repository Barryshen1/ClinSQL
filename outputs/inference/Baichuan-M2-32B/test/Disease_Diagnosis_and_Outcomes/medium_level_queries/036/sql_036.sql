WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 39 AND 49
),
hf_admissions AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
  GROUP BY d.hadm_id
),
admissions_with_hf AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  JOIN hf_admissions h ON a.hadm_id = h.hadm_id
  WHERE a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Comorbidity count: distinct ICD codes excluding HF
    COUNT(DISTINCT CASE WHEN LOWER(dd.long_title) NOT LIKE '%heart failure%' THEN d.icd_code END) AS comorbidity_count,
    -- CKD flag
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS ckd_flag,
    -- Diabetes flag
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS diabetes_flag
  FROM admissions_with_hf a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
cohort_with_tertiles AS (
  SELECT 
    *,
    CASE 
      WHEN NTILE(3) OVER (ORDER BY COALESCE(comorbidity_count, 0)) = 1 THEN 'Low'
      WHEN NTILE(3) OVER (ORDER BY COALESCE(comorbidity_count, 0)) = 2 THEN 'Med'
      ELSE 'High'
    END AS comorbidity_tertile
  FROM cohort
),
mortality_table AS (
  SELECT 
    CASE 
      WHEN los <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_group,
    comorbidity_tertile,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
    NULL AS ckd_prevalence,
    NULL AS diabetes_prevalence
  FROM cohort_with_tertiles
  GROUP BY los_group, comorbidity_tertile
),
prevalence AS (
  SELECT 
    (SELECT COUNT(*) FROM cohort WHERE ckd_flag = 1) * 100.0 / (SELECT COUNT(*) FROM cohort) AS ckd_prevalence,
    (SELECT COUNT(*) FROM cohort WHERE diabetes_flag = 1) * 100.0 / (SELECT COUNT(*) FROM cohort) AS diabetes_prevalence
)
SELECT 
  los_group,
  comorbidity_tertile,
  n,
  mortality_rate,
  ckd_prevalence,
  diabetes_prevalence
FROM mortality_table
UNION ALL
SELECT 
  'Overall' AS los_group,
  'Prevalence' AS comorbidity_tertile,
  NULL,
  NULL,
  (SELECT ckd_prevalence FROM prevalence),
  (SELECT diabetes_prevalence FROM prevalence);