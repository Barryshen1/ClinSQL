WITH cohort AS (
  -- Base cohort: male 52-62 with stroke
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Check if had ICU stay
    CASE WHEN MAX(icu.stay_id) IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_group,
    -- Comorbidity: count chronic conditions (hypertension, diabetes, ckd, heart failure)
    COUNT(DISTINCT 
      CASE WHEN diag.icd_code LIKE 'I10%' OR diag.icd_code LIKE 'I11%' OR diag.icd_code LIKE 'I12%' 
            OR diag.icd_code LIKE 'I13%' OR diag.icd_code LIKE 'I15%'
            OR diag.icd_code LIKE '401%' OR diag.icd_code LIKE '402%' OR diag.icd_code LIKE '403%'
            OR diag.icd_code LIKE '404%' OR diag.icd_code LIKE '405%' THEN 'HTN'
          WHEN diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%'
            OR diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%' OR diag.icd_code LIKE '250%' THEN 'DM'
          WHEN diag.icd_code LIKE 'N18%' OR diag.icd_code LIKE '585%' THEN 'CKD'
          WHEN diag.icd_code LIKE 'I50%' OR diag.icd_code LIKE '428%' THEN 'HF'
      END
    ) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
      diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%' 
      OR diag.icd_code LIKE 'I63%' OR diag.icd_code LIKE 'I64%' OR diag.icd_code LIKE 'I65%' 
      OR diag.icd_code LIKE 'I66%' OR diag.icd_code LIKE 'I67%' OR diag.icd_code LIKE 'I68%' 
      OR diag.icd_code LIKE 'I69%' 
      OR diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%' 
      OR diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '435%' 
      OR diag.icd_code LIKE '436%' OR diag.icd_code LIKE '437%' OR diag.icd_code LIKE '438%'
    )
  GROUP BY adm.subject_id, adm.hadm_id, adm.hospital_expire_flag, los_days
),

comorbidity_tertiles AS (
  -- Compute tertiles for comorbidity_count
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    los_days,
    icu_group,
    comorbidity_count,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile
  FROM cohort
),

conditions AS (
  -- Mark CKD and diabetes per patient
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    MAX(CASE WHEN diag.icd_code LIKE 'N18%' OR diag.icd_code LIKE '585%' THEN 1 ELSE 0 END) AS ckd,
    MAX(CASE WHEN diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%'
              OR diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%' OR diag.icd_code LIKE '250%' THEN 1 ELSE 0 END) AS diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
      diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%' 
      OR diag.icd_code LIKE 'I63%' OR diag.icd_code LIKE 'I64%' OR diag.icd_code LIKE 'I65%' 
      OR diag.icd_code LIKE 'I66%' OR diag.icd_code LIKE 'I67%' OR diag.icd_code LIKE 'I68%' 
      OR diag.icd_code LIKE 'I69%' 
      OR diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%' 
      OR diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '435%' 
      OR diag.icd_code LIKE '436%' OR diag.icd_code LIKE '437%' OR diag.icd_code LIKE '438%'
    )
  GROUP BY adm.subject_id, adm.hadm_id
)

SELECT 
  ct.icu_group,
  CASE WHEN ct.los_days <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
  ct.comorbidity_tertile,
  COUNT(*) AS n_patients,
  ROUND(100.0 * SUM(ct.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  ROUND(100.0 * SUM(c.ckd) / COUNT(*), 2) AS ckd_percent,
  ROUND(100.0 * SUM(c.diabetes) / COUNT(*), 2) AS diabetes_percent
FROM comorbidity_tertiles ct
INNER JOIN conditions c
  ON ct.subject_id = c.subject_id AND ct.hadm_id = c.hadm_id
GROUP BY ct.icu_group, los_group, ct.comorbidity_tertile
ORDER BY ct.icu_group, los_group, ct.comorbidity_tertile;