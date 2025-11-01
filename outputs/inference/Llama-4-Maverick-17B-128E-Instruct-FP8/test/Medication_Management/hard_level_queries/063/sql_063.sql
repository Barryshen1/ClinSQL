WITH 
-- Step 1: Filter patients by age, gender, and diagnosis (pneumonia)
pneumonia_patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.anchor_age BETWEEN 48 AND 58
  AND p.gender = 'M'
  AND d_diag.long_title LIKE '%Pneumonia%'
),

-- Step 2: Identify medications used in the first 24 hours
early_meds AS (
  SELECT pp.subject_id, pp.hadm_id, COUNT(DISTINCT p.drug) AS num_meds
  FROM pneumonia_patients pp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON pp.hadm_id = p.hadm_id
  WHERE p.starttime <= pp.admittime + INTERVAL 1 DAY
  GROUP BY pp.subject_id, pp.hadm_id
),

-- Step 3: Assess serotonergic-interaction risk (simplified example)
serotonergic_risk AS (
  SELECT em.subject_id, em.hadm_id, 
         COUNT(CASE WHEN LOWER(p.drug) LIKE '%sertraline%' OR LOWER(p.drug) LIKE '%fluoxetine%' THEN 1 END) AS serotonergic_meds
  FROM early_meds em
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON em.hadm_id = p.hadm_id
  WHERE p.starttime <= (SELECT admittime FROM pneumonia_patients pp WHERE pp.hadm_id = em.hadm_id) + INTERVAL 1 DAY
  GROUP BY em.subject_id, em.hadm_id
),

-- Step 4: Calculate LOS and mortality
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),

patient_outcomes AS (
  SELECT pp.subject_id, pp.hadm_id,
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los,
         a.hospital_expire_flag AS hospital_mortality,
         icu.stay_id IS NOT NULL AS icu_admission,
         sr.serotonergic_meds > 0 AS serotonergic_risk
  FROM pneumonia_patients pp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON pp.hadm_id = a.hadm_id
  LEFT JOIN icu_stays icu ON pp.hadm_id = icu.hadm_id
  LEFT JOIN serotonergic_risk sr ON pp.hadm_id = sr.hadm_id
)

-- Final analysis
SELECT 
  -- Medication complexity distribution
  APPROX_QUANTILES(em.num_meds, 100)[OFFSET(25)] AS p25_meds,
  APPROX_QUANTILES(em.num_meds, 100)[OFFSET(50)] AS p50_meds,
  APPROX_QUANTILES(em.num_meds, 100)[OFFSET(75)] AS p75_meds,
  AVG(em.num_meds) AS mean_meds,
  
  -- LOS and mortality comparison
  AVG(po.hospital_los) AS avg_hospital_los_hours,
  SUM(CAST(po.serotonergic_risk AS INT64)) / COUNT(*) AS serotonergic_risk_proportion,
  SUM(CAST(po.icu_admission AS INT64)) / COUNT(*) AS icu_admission_proportion,
  SUM(CAST(po.hospital_mortality AS INT64)) / COUNT(*) AS hospital_mortality_proportion
  
FROM pneumonia_patients pp
JOIN early_meds em ON pp.hadm_id = em.hadm_id
JOIN patient_outcomes po ON pp.hadm_id = po.hadm_id;