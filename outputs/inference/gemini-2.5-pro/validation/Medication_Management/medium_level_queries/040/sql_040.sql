WITH
  -- Step 1: Define the patient cohort: males, 36-46, with both diabetes and heart failure.
  cohort_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 36 AND 46
      -- Use EXISTS for an efficient check for the presence of each condition per admission
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
          ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
        WHERE
          dx.hadm_id = adm.hadm_id
          AND LOWER(d_dx.long_title) LIKE '%diabetes%'
      )
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
          ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
        WHERE
          dx.hadm_id = adm.hadm_id
          AND LOWER(d_dx.long_title) LIKE '%heart failure%'
      )
  ),

  -- Step 2: Get the total number of unique patients in the cohort for the prevalence denominator.
  total_cohort_patients AS (
    SELECT COUNT(DISTINCT subject_id) AS total_patients
    FROM cohort_admissions
  ),

  -- Step 3: Identify and classify relevant drug prescriptions for the cohort.
  classified_prescriptions AS (
    SELECT
      c.subject_id,
      p.starttime,
      c.admittime,
      c.dischtime,
      CASE
        -- Antidiabetic Drugs
        WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%januvia%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%jardiance%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%'
          THEN 'Antidiabetic'
        -- Cardiac Drugs
        WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%carvedilol%' OR LOWER(p.drug) LIKE '%labetalol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%bisoprolol%' OR LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%ramipril%' OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' OR LOWER(p.drug) LIKE '%irbesartan%' OR LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%' OR LOWER(p.drug) LIKE '%hydrochlorothiazide%' OR LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%clopidogrel%' OR LOWER(p.drug) LIKE '%atorvastatin%' OR LOWER(p.drug) LIKE '%rosuvastatin%' OR LOWER(p.drug) LIKE '%simvastatin%' OR LOWER(p.drug) LIKE '%digoxin%' OR LOWER(p.drug) LIKE '%amiodarone%' OR LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%' OR LOWER(p.drug) LIKE '%warfarin%' OR LOWER(p.drug) LIKE '%apixaban%' OR LOWER(p.drug) LIKE '%rivaroxaban%'
          THEN 'Cardiac'
        ELSE NULL
      END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    INNER JOIN cohort_admissions AS c
      ON p.hadm_id = c.hadm_id
    WHERE
      p.starttime IS NOT NULL
  ),

  -- Step 4: Flag prescriptions based on the first 48h and last 12h time windows.
  timed_prescriptions AS (
    SELECT
      subject_id,
      drug_class,
      (starttime <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR)) AS in_first_48h,
      (starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND starttime <= dischtime) AS in_last_12h
    FROM classified_prescriptions
    WHERE
      drug_class IS NOT NULL
  )

-- Step 5: Final aggregation to calculate prevalence and difference.
SELECT
  tp.drug_class,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN tp.in_first_48h THEN tp.subject_id END), tcp.total_patients) * 100 AS prevalence_first_48h_pct,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN tp.in_last_12h THEN tp.subject_id END), tcp.total_patients) * 100 AS prevalence_last_12h_pct,
  (SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN tp.in_first_48h THEN tp.subject_id END), tcp.total_patients) * 100) - (SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN tp.in_last_12h THEN tp.subject_id END), tcp.total_patients) * 100) AS absolute_diff_pp
FROM timed_prescriptions AS tp, total_cohort_patients AS tcp
GROUP BY
  tp.drug_class,
  tcp.total_patients
ORDER BY
  tp.drug_class;