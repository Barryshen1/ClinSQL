WITH cohort AS (
  -- Get male patients aged 36-46 with both diabetes and heart failure
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.hadm_id IN (
      -- Diabetes diagnosis
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E1%' AND icd_version = 10
      INTERSECT DISTINCT
      -- Heart failure diagnosis
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%' AND icd_version = 10
    )
),

drug_classes AS (
  -- Map drug names to classes
  SELECT
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%glipizide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%glyburide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%glimepiride%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%sitagliptin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%empagliflozin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%canagliflozin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%dapagliflozin%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%liraglutide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%semaglutide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%exenatide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%pioglitazone%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%rosiglitazone%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%nateglinide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%repaglinide%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%acarbose%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%miglitol%' THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%beta blocker%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%metoprolol%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%atenolol%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%carvedilol%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%bisoprolol%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%ace inhibitor%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%lisinopril%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%enalapril%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%ramipril%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%arb%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%losartan%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%valsartan%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%diuretic%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%furosemide%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%hydrochlorothiazide%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%spironolactone%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%eplerenone%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%digoxin%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%statin%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%atorvastatin%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%simvastatin%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%rosuvastatin%' THEN 'Cardiac'
      WHEN LOWER(drug) LIKE '%pravastatin%' THEN 'Cardiac'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY drug
  HAVING drug_class IS NOT NULL
),

prescriptions_with_class AS (
  -- Join prescriptions with drug classes
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    dc.drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN drug_classes dc
    ON p.drug = dc.drug
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
),

time_windows AS (
  -- Define time windows for each admission
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATETIME_ADD(admittime, INTERVAL 48 HOUR) AS first48_end,
    DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AS last12_start
  FROM cohort
),

drugs_by_window AS (
  -- Check if each class was given in first48 or last12
  SELECT
    tw.subject_id,
    tw.hadm_id,
    p.drug_class,
    MAX(CASE
        WHEN p.starttime <= tw.first48_end AND (p.stoptime >= tw.admittime OR p.stoptime IS NULL)
        THEN 1 ELSE 0 END) AS in_first48,
    MAX(CASE
        WHEN p.starttime <= tw.dischtime AND (p.stoptime >= tw.last12_start OR p.stoptime IS NULL)
        THEN 1 ELSE 0 END) AS in_last12
  FROM time_windows tw
  LEFT JOIN prescriptions_with_class p
    ON tw.hadm_id = p.hadm_id
      AND p.starttime <= tw.dischtime
      AND (p.stoptime >= tw.admittime OR p.stoptime IS NULL)
  GROUP BY tw.subject_id, tw.hadm_id, p.drug_class
),

aggregated AS (
  -- Count patients per class and window
  SELECT
    drug_class,
    COUNT(DISTINCT subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN in_first48 = 1 THEN subject_id END) AS first48_count,
    COUNT(DISTINCT CASE WHEN in_last12 = 1 THEN subject_id END) AS last12_count
  FROM drugs_by_window
  GROUP BY drug_class
)

-- Calculate prevalence and difference
SELECT
  drug_class,
  total_patients,
  ROUND(100.0 * first48_count / total_patients, 1) AS first48_percent,
  ROUND(100.0 * last12_count / total_patients, 1) AS last12_percent,
  ROUND(100.0 * first48_count / total_patients - 100.0 * last12_count / total_patients, 1) AS absolute_difference_pp
FROM aggregated
ORDER BY drug_class;