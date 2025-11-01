WITH
  -- 1. Identify the target cohort: Male ICU patients aged 62-72
  cohort_patients AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      icu.stay_id,
      -- Calculate the patient's age at the time of admission
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp`.patients AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp`.admissions AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu`.icustays AS icu
      ON a.hadm_id = icu.hadm_id
    WHERE
      p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 62 AND 72
  ),

  -- 2. Calculate the mean heart rate for each ICU stay within the cohort
  mean_heart_rates AS (
    SELECT
      ce.stay_id,
      AVG(ce.valuenum) AS mean_hr
    FROM
      `physionet-data.mimiciv_3_1_icu`.chartevents AS ce
    WHERE
      ce.itemid = 220045 -- ItemID for Heart Rate (from d_items)
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0 -- Exclude non-positive values for meaningful average
    GROUP BY
      ce.stay_id
  ),

  -- 3. Identify admissions with an Acute Myocardial Infarction (MI) diagnosis
  acute_mi_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE
      (icd_version = 9 AND icd_code LIKE '410%') -- ICD-9 codes for Acute MI (e.g., 410.0-410.9)
      OR (icd_version = 10 AND icd_code LIKE 'I21%') -- ICD-10 codes for Acute MI (e.g., I21.0-I21.9)
  ),

  -- 4. Combine cohort details with mean heart rates and MI status, and categorize HR
  combined_cohort_data AS (
    SELECT
      cp.subject_id,
      cp.hadm_id,
      cp.stay_id,
      mhr.mean_hr,
      CASE
        WHEN mhr.mean_hr IS NULL THEN 'No HR Data'
        WHEN mhr.mean_hr < 60 THEN '<60 bpm'
        WHEN mhr.mean_hr BETWEEN 60 AND 99 THEN '60-99 bpm'
        WHEN mhr.mean_hr BETWEEN 100 AND 119 THEN '100-119 bpm'
        WHEN mhr.mean_hr >= 120 THEN '>=120 bpm'
        ELSE 'No HR Data' -- Fallback for any unexpected cases, though mhr.mean_hr IS NULL should catch most
      END AS heart_rate_category,
      CASE
        WHEN ami.hadm_id IS NOT NULL THEN 1
        ELSE 0
      END AS has_acute_mi_flag -- Flag indicates if the admission (and thus the stay) had an acute MI
    FROM
      cohort_patients AS cp
    LEFT JOIN
      mean_heart_rates AS mhr
      ON cp.stay_id = mhr.stay_id
    LEFT JOIN
      acute_mi_admissions AS ami
      ON cp.hadm_id = ami.hadm_id
  )

-- 5. Final aggregation based on heart rate category
SELECT
  cd.heart_rate_category,
  COUNT(cd.stay_id) AS num_icu_stays, -- Count of ICU stays in each category
  ROUND(SUM(cd.has_acute_mi_flag) * 100.0 / COUNT(cd.stay_id), 2) AS percent_with_acute_mi
FROM
  combined_cohort_data AS cd
GROUP BY
  cd.heart_rate_category
ORDER BY
  -- Custom order to ensure categories are displayed logically
  CASE
    WHEN cd.heart_rate_category = '<60 bpm' THEN 1
    WHEN cd.heart_rate_category = '60-99 bpm' THEN 2
    WHEN cd.heart_rate_category = '100-119 bpm' THEN 3
    WHEN cd.heart_rate_category = '>=120 bpm' THEN 4
    WHEN cd.heart_rate_category = 'No HR Data' THEN 5
    ELSE 99 -- For any 'Other' categories
  END;