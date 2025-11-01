WITH base_patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' 
    AND anchor_age BETWEEN 51 AND 61
),

index_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_bucket
  FROM base_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE a.admission_type = 'SURG'
    AND icd.icd_code LIKE 'T81.%'
    AND a.hospital_expire_flag = 0  -- Exclude immediate deaths
    AND (a.deathtime IS NULL OR a.deathtime > a.admittime)
  -- Deduplicate to first admission per patient
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

icu_cohort AS (
  SELECT 
    ia.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS in_icu
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON ia.hadm_id = i.hadm_id
),

-- CCI calculation (simplified weights for common conditions; historical)
prior_adms AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    icd_code,
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` aa 
    ON di.hadm_id = aa.hadm_id
),

cci_scores AS (
  SELECT 
    ic.*,
    COALESCE(
      SUM(CASE 
        -- MI
        WHEN pr.icd_code LIKE 'I21.%' OR pr.icd_code LIKE 'I22.%' THEN 1
        -- CHF
        WHEN pr.icd_code LIKE 'I09.9' OR pr.icd_code LIKE 'I11.0' OR pr.icd_code LIKE 'I13.%' 
             OR pr.icd_code LIKE 'I25.5' OR pr.icd_code LIKE 'I42.%' OR pr.icd_code LIKE 'I43.%' 
             OR pr.icd_code LIKE 'I50.%' THEN 1
        -- PVD
        WHEN pr.icd_code LIKE 'I70.%' THEN 1
        -- Dementia
        WHEN pr.icd_code LIKE 'F01.%' OR pr.icd_code LIKE 'F02.%' OR pr.icd_code LIKE 'F03.%' THEN 1
        -- COPD
        WHEN pr.icd_code LIKE 'J40.%' OR pr.icd_code LIKE 'J41.%' OR pr.icd_code LIKE 'J42.%' 
             OR pr.icd_code LIKE 'J43.%' OR pr.icd_code LIKE 'J44.%' OR pr.icd_code LIKE 'J47.%' THEN 1
        -- Connective tissue
        WHEN pr.icd_code LIKE 'M05.%' OR pr.icd_code LIKE 'M06.%' OR pr.icd_code LIKE 'M08.%' 
             OR pr.icd_code LIKE 'M12.%' OR pr.icd_code LIKE 'M32.%' OR pr.icd_code LIKE 'M33.%' 
             OR pr.icd_code LIKE 'M34.%' THEN 1
        -- Peptic ulcer
        WHEN pr.icd_code LIKE 'K25.%' OR pr.icd_code LIKE 'K26.%' OR pr.icd_code LIKE 'K27.%' OR pr.icd_code LIKE 'K28.%' THEN 1
        -- Uncomplicated DM
        WHEN pr.icd_code IN ('E10.0', 'E10.1', 'E10.9', 'E11.0', 'E11.1', 'E11.9', 'E13.0', 'E13.1', 'E13.9') THEN 1
        -- Complicated DM (fixed pattern: use LIKE for subcodes starting with .2, .3, .4)
        WHEN pr.icd_code LIKE 'E10.2%' OR pr.icd_code LIKE 'E10.3%' OR pr.icd_code LIKE 'E10.4%' 
             OR pr.icd_code LIKE 'E11.2%' OR pr.icd_code LIKE 'E11.3%' OR pr.icd_code LIKE 'E11.4%' 
             OR pr.icd_code LIKE 'E13.2%' OR pr.icd_code LIKE 'E13.3%' OR pr.icd_code LIKE 'E13.4%' THEN 2
        -- Paraplegia
        WHEN pr.icd_code LIKE 'G81.%' OR pr.icd_code LIKE 'G82.%' OR pr.icd_code LIKE 'G83.2' OR pr.icd_code LIKE 'G83.4' THEN 2
        -- Renal
        WHEN pr.icd_code LIKE 'N18.%' OR pr.icd_code LIKE 'N19.%' OR pr.icd_code LIKE 'I12.%' OR pr.icd_code LIKE 'I13.1' THEN 2
        -- Cancer (non-metastatic): simplified to cover C00-C96 (excluding metastatic)
        WHEN pr.icd_code LIKE 'C[0-6][0-9].[%]' OR pr.icd_code LIKE 'C7[0-9].[%]' OR pr.icd_code LIKE 'C[0-9][0-9].[%]' 
             AND NOT (pr.icd_code LIKE 'C77.%' OR pr.icd_code LIKE 'C78.%' OR pr.icd_code LIKE 'C79.%') THEN 2
        -- Liver (moderate)
        WHEN pr.icd_code IN ('K70.0', 'K70.3', 'K71.1') OR pr.icd_code LIKE 'K73.%' OR pr.icd_code LIKE 'K74.%' THEN 2
        -- Metastatic cancer
        WHEN pr.icd_code LIKE 'C77.%' OR pr.icd_code LIKE 'C78.%' OR pr.icd_code LIKE 'C79.%' OR pr.icd_code LIKE 'C80.%' THEN 3
        -- Liver (severe)
        WHEN pr.icd_code IN ('I85.0', 'I85.1', 'I86.4', 'K70.4', 'K72.1') OR pr.icd_code LIKE 'K76.6%' OR pr.icd_code LIKE 'K76.7%' THEN 3
        -- HIV
        WHEN pr.icd_code LIKE 'B20.%' OR pr.icd_code LIKE 'B21.%' OR pr.icd_code LIKE 'B22.%' OR pr.icd_code LIKE 'B24.%' THEN 1
        ELSE 0 
      END), 0
    ) AS cci_score
  FROM icu_cohort ic
  LEFT JOIN prior_adms pr 
    ON ic.subject_id = pr.subject_id 
    AND pr.admittime < ic.admittime
  GROUP BY ic.subject_id, ic.hadm_id, ic.admittime, ic.dischtime, ic.hospital_expire_flag, 
           ic.admission_type, ic.los_bucket, ic.los_days, ic.in_icu
),

buckets AS (
  SELECT 
    *,
    CASE 
      WHEN cci_score BETWEEN 0 AND 1 THEN '0-1'
      WHEN cci_score = 2 THEN '2'
      ELSE '>=3'
    END AS cci_bucket,
    -- CKD and DM in index admission
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx 
      WHERE dx.hadm_id = cci_scores.hadm_id AND dx.icd_code LIKE 'N18.%'
    ) THEN 1 ELSE 0 END AS has_ckd,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx 
      WHERE dx.hadm_id = cci_scores.hadm_id 
        AND (dx.icd_code LIKE 'E10.%' OR dx.icd_code LIKE 'E11.%' OR dx.icd_code LIKE 'E13.%')
    ) THEN 1 ELSE 0 END AS has_diabetes
  FROM cci_scores
),

metrics AS (
  SELECT 
    in_icu,
    los_bucket,
    cci_bucket,
    COUNT(*) AS n_patients,
    SUM(hospital_expire_flag) AS n_deaths,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,  -- 50th percentile
    SUM(has_ckd) AS n_ckd,
    SUM(has_diabetes) AS n_diabetes
  FROM buckets
  GROUP BY in_icu, los_bucket, cci_bucket
)

SELECT 
  CASE WHEN in_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS stratification,
  los_bucket,
  cci_bucket,
  n_patients,
  ROUND((n_deaths / n_patients * 100), 2) AS mortality_pct,
  median_los,
  ROUND((n_ckd / n_patients * 100), 2) AS ckd_prevalence_pct,
  ROUND((n_diabetes / n_patients * 100), 2) AS diabetes_prevalence_pct
FROM metrics
ORDER BY stratification, los_bucket, cci_bucket;