WITH patients_filtered AS (
  SELECT p.subject_id, 
         p.anchor_age, 
         p.anchor_year, 
         p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
),
admissions_with_age AS (
  SELECT a.subject_id, 
         a.hadm_id, 
         a.admittime, 
         a.dischtime,
         p.anchor_age,
         p.anchor_year,
         (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),
icu_stays_long AS (
  SELECT i.subject_id, 
         i.hadm_id, 
         i.stay_id, 
         i.intime, 
         i.outtime, 
         i.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  WHERE i.los >= 6  -- >= 6 days = 144 hours
),
diagnoses AS (
  SELECT d.hadm_id,
         MAX(CASE 
           WHEN (d.icd_code LIKE 'E11%' OR 
                 d.icd_code IN ('E08', 'E08.9', 'E09', 'E09.9', 'E10', 'E10.9', 'E13', 'E13.9')) 
             THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE 
           WHEN d.icd_code LIKE 'I50%' OR 
                d.icd_code IN ('I11.0', 'I13.0') 
             THEN 1 ELSE 0 END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY d.hadm_id
),
cohort AS (
  SELECT i.subject_id, 
         i.hadm_id, 
         i.stay_id, 
         i.intime, 
         i.outtime
  FROM icu_stays_long i
  INNER JOIN admissions_with_age a ON i.hadm_id = a.hadm_id
  INNER JOIN diagnoses d ON i.hadm_id = d.hadm_id
  WHERE d.has_diabetes = 1 
    AND d.has_heart_failure = 1
),
drug_mapping AS (
  SELECT drug, 
    CASE 
      WHEN LOWER(drug) LIKE '%insulin%' OR 
           LOWER(drug) IN ('glargine', 'detemir', 'degludec', 'aspart', 'lispro', 'glulisine', 'nph', 'neutral protamine') 
      THEN 'antidiabetics'
      WHEN LOWER(drug) IN ('metoprolol', 'carvedilol', 'labetalol', 'bisoprolol', 'atenolol', 'propranolol', 'nadolol', 'esmolol')
      THEN 'beta_blockers'
      WHEN LOWER(drug) IN ('lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril', 'fosinopril', 'moexipril', 'perindopril', 'quinapril', 'trandolapril',
                           'losartan', 'valsartan', 'irbesartan', 'candesartan', 'olmesartan', 'telmisartan', 'eprosartan',
                           'sacubitril/valsartan', 'entresto')
      THEN 'acei_arb_arni'
      WHEN LOWER(drug) IN ('furosemide', 'lasix', 'bumetanide', 'torsemide', 'demadex')
      THEN 'loop_diuretics'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE drug IS NOT NULL
),
drug_exposure AS (
  SELECT c.subject_id,
         c.stay_id,
         dm.drug_class,
         -- First 72h: any overlap with [intime, intime + 72h]
         MAX(CASE 
           WHEN p.starttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR) AND
                COALESCE(p.stoptime, c.outtime) >= c.intime
           THEN 1 ELSE 0 END) AS on_first_72h,
         -- Final 72h: any overlap with [outtime - 72h, outtime]
         MAX(CASE 
           WHEN p.starttime <= c.outtime AND
                COALESCE(p.stoptime, c.outtime) >= DATETIME_SUB(c.outtime, INTERVAL 72 HOUR)
           THEN 1 ELSE 0 END) AS on_final_72h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p ON c.hadm_id = p.hadm_id
  INNER JOIN drug_mapping dm ON LOWER(p.drug) = LOWER(dm.drug)
  WHERE dm.drug_class IS NOT NULL
  GROUP BY c.subject_id, c.stay_id, dm.drug_class
),
classification AS (
  SELECT drug_class,
         SUM(on_first_72h) AS first_count,
         SUM(on_final_72h) AS final_count,
         COUNT(*) AS total_patients,
         SUM(CASE WHEN on_first_72h = 1 AND on_final_72h = 1 THEN 1 ELSE 0 END) AS continued,
         SUM(CASE WHEN on_first_72h = 0 AND on_final_72h = 1 THEN 1 ELSE 0 END) AS initiated,
         SUM(CASE WHEN on_first_72h = 1 AND on_final_72h = 0 THEN 1 ELSE 0 END) AS discontinued
  FROM drug_exposure
  GROUP BY drug_class
)
SELECT 
  drug_class,
  ROUND(100.0 * first_count / total_patients, 2) AS pct_first_72h,
  ROUND(100.0 * final_count / total_patients, 2) AS pct_final_72h,
  continued,
  initiated,
  discontinued
FROM classification
ORDER BY drug_class;