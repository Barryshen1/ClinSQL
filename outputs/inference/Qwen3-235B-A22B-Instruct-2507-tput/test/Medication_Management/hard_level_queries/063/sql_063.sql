WITH
  -- Step 1: Get male patients aged 48-58
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.patients
    WHERE gender = 'M'
      AND anchor_age BETWEEN 48 AND 58
  ),
  
  -- Step 2: Get admissions with pneumonia diagnosis (ICD-10)
  pneumonia_admissions AS (
    SELECT DISTINCT a.hadm_id, a.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%pneumonia%'
      AND d.icd_version = 10
  ),
  
  -- Step 3: Combine patients and admissions
  target_admissions AS (
    SELECT pa.hadm_id, pa.subject_id
    FROM pneumonia_admissions pa
    INNER JOIN eligible_patients ep ON pa.subject_id = ep.subject_id
  ),
  
  -- Step 4: Get admission details with ICU flag and time bounds
  admission_details AS (
    SELECT a.hadm_id, a.admittime, a.dischtime,
           DATETIME_ADD(a.admittime, INTERVAL 24 HOUR) AS day1_end,
           a.hospital_expire_flag,
           COALESCE(i.stay_id IS NOT NULL, FALSE) AS icu_admission
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
      ON a.hadm_id = i.hadm_id
    WHERE a.hadm_id IN (SELECT hadm_id FROM target_admissions)
  ),
  
  -- Step 5: Get prescriptions in first 24 hours of admission
  meds_first_24h AS (
    SELECT p.hadm_id, p.drug,
           CASE
             WHEN LOWER(p.drug) IN (
               'sertraline', 'fluoxetine', 'paroxetine', 'citalopram', 'escitalopram',
               'venlafaxine', 'duloxetine', 'desvenlafaxine', 'tramadol',
               'dextromethorphan', 'ondansetron', 'granisetron', 'palonosetron',
               'imipramine', 'amitriptyline', 'clomipramine', 'mirtazapine',
               'trazodone', 'bupropion', 'milnacipran', 'levomilnacipran'
             ) THEN 1
             ELSE 0
           END AS is_serotonergic
    FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    INNER JOIN admission_details a ON p.hadm_id = a.hadm_id
    WHERE p.starttime IS NOT NULL
      AND p.starttime >= a.admittime
      AND p.starttime < a.day1_end
      AND p.drug IS NOT NULL
  ),
  
  -- Step 6: Medication complexity per admission (count of distinct drugs)
  med_complexity AS (
    SELECT hadm_id,
           COUNT(DISTINCT drug) AS drug_count,
           MAX(is_serotonergic) AS serotonergic_flag
    FROM meds_first_24h
    GROUP BY hadm_id
  ),
  
  -- Step 7: Combine with outcomes
  cohort_outcomes AS (
    SELECT a.hadm_id,
           a.icu_admission,
           mc.serotonergic_flag,
           mc.drug_count,
           a.hospital_expire_flag,
           DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM admission_details a
    INNER JOIN med_complexity mc ON a.hadm_id = mc.hadm_id
    WHERE a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
  ),
  
  -- Step 8: Compute medication complexity distribution
  complexity_stats AS (
    SELECT
      AVG(drug_count) AS mean_complexity,
      PERCENTILE_CONT(drug_count, 0.25) OVER() AS p25_complexity,
      PERCENTILE_CONT(drug_count, 0.50) OVER() AS p50_complexity,
      PERCENTILE_CONT(drug_count, 0.75) OVER() AS p75_complexity
    FROM med_complexity
    LIMIT 1
  ),
  
  -- Step 9: Compare LOS and mortality by serotonergic and ICU status
  outcome_stats AS (
    SELECT
      serotonergic_flag,
      icu_admission,
      AVG(los_days) AS mean_los,
      PERCENTILE_CONT(los_days, 0.75) OVER(PARTITION BY serotonergic_flag, icu_admission) AS los_p75,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM cohort_outcomes
    GROUP BY serotonergic_flag, icu_admission, los_days
  )

-- Final output: complexity distribution and outcome comparisons
SELECT
  cs.mean_complexity,
  cs.p25_complexity,
  cs.p50_complexity,
  cs.p75_complexity,
  os.serotonergic_flag,
  os.icu_admission,
  os.mean_los,
  os.los_p75,
  os.mortality_rate
FROM complexity_stats cs
CROSS JOIN outcome_stats os;