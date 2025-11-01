WITH patients_cohort AS (
  -- Males aged 52-62
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),

sepsis_adms AS (
  -- Admissions with sepsis (ICD-9/10 codes)
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, 
         a.hospital_expire_flag, a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_cohort p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code 
    AND CAST(d.icd_version AS STRING) = CAST(icd.icd_version AS INT64)
  WHERE (
    -- ICD-10 sepsis
    (CAST(d.icd_version AS STRING) = '10' AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%'))
    OR
    -- ICD-9 sepsis
    (CAST(d.icd_version AS STRING) = '9' AND (d.icd_code LIKE '038%' OR d.icd_code = '785.52'))
  )
    AND icd.long_title IS NOT NULL  -- Valid diagnosis
),

comorb_count AS (
  -- Count non-sepsis diagnoses per admission (comorbidities)
  SELECT 
    sa.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM sepsis_adms sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON sa.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code 
    AND CAST(d.icd_version AS STRING) = CAST(icd.icd_version AS INT64)
  WHERE d.icd_code IS NOT NULL
    AND NOT (
      -- Exclude sepsis codes from count
      (CAST(d.icd_version AS STRING) = '10' AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%'))
      OR
      (CAST(d.icd_version AS STRING) = '9' AND (d.icd_code LIKE '038%' OR d.icd_code = '785.52'))
    )
    AND icd.long_title IS NOT NULL
  GROUP BY sa.hadm_id
),

septic_shock_flag AS (
  -- Flag admissions with septic shock
  SELECT 
    sa.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = sa.hadm_id
          AND (
            (CAST(d.icd_version AS STRING) = '10' AND d.icd_code LIKE 'R65.2%')
            OR (CAST(d.icd_version AS STRING) = '9' AND d.icd_code = '785.52')
          )
      ) THEN 'Septic Shock'
      ELSE 'No Shock'
    END AS sepsis_severity
  FROM sepsis_adms sa
)

SELECT 
  ssf.sepsis_severity,
  CASE 
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) >= 8 THEN '>=8 days'
    ELSE 'Other'  -- Rare cases (LOS=0 or NULL)
  END AS los_category,
  a.admission_type,
  ROUND(AVG(a.hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(COALESCE(cc.comorbidity_count, 0)), 2) AS mean_comorbidity_count,
  COUNT(*) AS n_patients
FROM sepsis_adms a
INNER JOIN septic_shock_flag ssf ON a.hadm_id = ssf.hadm_id
LEFT JOIN comorb_count cc ON a.hadm_id = cc.hadm_id
WHERE DATE_DIFF(a.dischtime, a.admittime, DAY) IS NOT NULL
  AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0  -- Valid LOS
GROUP BY ssf.sepsis_severity, los_category, a.admission_type
ORDER BY ssf.sepsis_severity, 
         CASE los_category 
           WHEN '1-3 days' THEN 1 
           WHEN '4-7 days' THEN 2 
           WHEN '>=8 days' THEN 3 
           ELSE 4 
         END,
         a.admission_type;