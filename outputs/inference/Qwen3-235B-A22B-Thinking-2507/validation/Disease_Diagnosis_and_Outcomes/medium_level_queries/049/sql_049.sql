WITH 
-- Step 1: Filter patients (men 51-61) and compute age
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
),

-- Step 2: Identify STEMI/NSTEMI admissions (mutually exclusive)
mi_diagnoses AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND (icd_code LIKE '4100%' OR icd_code LIKE '4101%' OR icd_code LIKE '4102%' 
                         OR icd_code LIKE '4103%' OR icd_code LIKE '4104%' OR icd_code LIKE '4105%' OR icd_code LIKE '4106%'))
               OR (icd_version = 10 AND (icd_code LIKE 'I210%' OR icd_code LIKE 'I211%' OR icd_code LIKE 'I212%' OR icd_code LIKE 'I213%')) 
          THEN 1 ELSE 0 
        END) AS is_stemi,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '4107%')
               OR (icd_version = 10 AND icd_code LIKE 'I214%') 
          THEN 1 ELSE 0 
        END) AS is_nstemi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
mi_cohort AS (
  SELECT 
    pf.*,
    CASE 
      WHEN is_stemi = 1 AND is_nstemi = 0 THEN 'STEMI'
      WHEN is_stemi = 0 AND is_nstemi = 1 THEN 'NSTEMI'
    END AS mi_type
  FROM patients_filtered pf
  INNER JOIN mi_diagnoses md
    ON pf.hadm_id = md.hadm_id
  WHERE (is_stemi = 1 AND is_nstemi = 0) 
     OR (is_stemi = 0 AND is_nstemi = 1)
),

-- Step 3: Compute comorbidities (corrected binary flags and total)
comorbidities AS (
  SELECT 
    hadm_id,
    ckd,
    diabetes,
    hypertension,
    chf,
    ckd + diabetes + hypertension + chf AS total_comorbidities
  FROM (
    SELECT 
      hadm_id,
      -- CKD flag
      MAX(CASE 
            WHEN (icd_version = 9 AND icd_code LIKE '585%') 
              OR (icd_version = 10 AND icd_code LIKE 'N18%') 
            THEN 1 ELSE 0 
          END) AS ckd,
      -- Diabetes flag
      MAX(CASE 
            WHEN (icd_version = 9 AND icd_code LIKE '250%') 
              OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' 
                     OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' 
                     OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%')) 
            THEN 1 ELSE 0 
          END) AS diabetes,
      -- Hypertension flag (corrected pattern matching)
      MAX(CASE 
            WHEN (icd_version = 9 AND (icd_code LIKE '401%' OR icd_code LIKE '402%' OR icd_code LIKE '403%' 
                                       OR icd_code LIKE '404%' OR icd_code LIKE '405%'))
                 OR (icd_version = 10 AND (icd_code LIKE 'I10%' OR icd_code LIKE 'I11%' 
                                           OR icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' 
                                           OR icd_code LIKE 'I15%'))
            THEN 1 ELSE 0 
          END) AS hypertension,
      -- CHF flag (corrected pattern matching)
      MAX(CASE 
            WHEN (icd_version = 9 AND icd_code LIKE '428%') 
                 OR (icd_version = 10 AND icd_code LIKE 'I50%') 
            THEN 1 ELSE 0 
          END) AS chf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  )
),
comorbidity_groups AS (
  SELECT 
    hadm_id,
    ckd,
    diabetes,
    CASE 
      WHEN total_comorbidities <= 1 THEN '0-1'
      WHEN total_comorbidities = 2 THEN '2'
      WHEN total_comorbidities >= 3 THEN '≥3'
    END AS comorbidity_group
  FROM comorbidities
),

-- Step 4: Compute LOS categories
los_categories AS (
  SELECT 
    hadm_id,
    -- Hospital LOS in days (inclusive of admission/discharge days)
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 BETWEEN 6 AND 9 THEN '6-9'
      WHEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 >= 10 THEN '≥10'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Final aggregation
SELECT 
  mc.mi_type,
  lc.los_group,
  cg.comorbidity_group,
  COUNT(*) AS N,
  ROUND(SUM(mc.hospital_expire_flag) * 100.0 / COUNT(*), 1) AS mortality_rate,
  ROUND(SUM(cg.ckd) * 100.0 / COUNT(*), 1) AS ckd_prevalence,
  ROUND(SUM(cg.diabetes) * 100.0 / COUNT(*), 1) AS diabetes_prevalence
FROM mi_cohort mc
INNER JOIN comorbidity_groups cg
  ON mc.hadm_id = cg.hadm_id
INNER JOIN los_categories lc
  ON mc.hadm_id = lc.hadm_id
GROUP BY mi_type, los_group, comorbidity_group
ORDER BY 
  mi_type,
  CASE los_group
    WHEN '1-2' THEN 1
    WHEN '3-5' THEN 2
    WHEN '6-9' THEN 3
    WHEN '≥10' THEN 4
    ELSE 5
  END,
  comorbidity_group;