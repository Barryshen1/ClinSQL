WITH
-- Step 1: Identify all hospital admissions for male patients aged 61-71.
patient_cohort AS (
  SELECT
    pat.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  WHERE
    pat.gender = 'M'
    -- Calculate age at admission and filter
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 61 AND 71
),

-- Step 2: Calculate the "medication complexity score" for each admission in the cohort.
-- The score is the number of unique medications administered in the first 24 hours.
med_complexity AS (
  SELECT
    cohort.hadm_id,
    COUNT(DISTINCT emar.medication) AS medication_complexity_score
  FROM
    patient_cohort AS cohort
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS emar
    ON cohort.hadm_id = emar.hadm_id
  WHERE
    -- Filter for administrations within the first 24 hours of hospital admission
    emar.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 24 HOUR)
  GROUP BY
    cohort.hadm_id
),

-- Step 3: For all admissions, find the next admission time to calculate readmissions.
-- This must be done on the full admissions table to catch any subsequent admission.
all_admissions_with_next AS (
  SELECT
    hadm_id,
    dischtime,
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Step 4: Combine the cohort with calculated metrics (LOS, complexity, readmission flag).
cohort_with_metrics AS (
  SELECT
    cohort.hadm_id,
    cohort.hospital_expire_flag,
    -- Calculate Length of Stay in days
    DATETIME_DIFF(cohort.dischtime, cohort.admittime, HOUR) / 24.0 AS los_days,
    -- Use LEFT JOIN and COALESCE to include patients with 0 medications (score = 0)
    COALESCE(mc.medication_complexity_score, 0) AS medication_complexity_score,
    -- Create a flag for 30-day readmission
    CASE
      WHEN DATETIME_DIFF(next_adm.next_admittime, cohort.dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM
    patient_cohort AS cohort
  LEFT JOIN
    med_complexity AS mc
    ON cohort.hadm_id = mc.hadm_id
  LEFT JOIN
    all_admissions_with_next AS next_adm
    ON cohort.hadm_id = next_adm.hadm_id
),

-- Step 5: Stratify the cohort into quintiles based on the medication complexity score.
admissions_in_quintiles AS (
  SELECT
    hadm_id,
    los_days,
    hospital_expire_flag,
    medication_complexity_score,
    readmitted_30_days,
    NTILE(5) OVER (ORDER BY medication_complexity_score) AS complexity_quintile
  FROM
    cohort_with_metrics
)

-- Step 6: Aggregate the metrics by quintile and report the final results.
SELECT
  complexity_quintile,
  COUNT(hadm_id) AS number_of_admissions,
  AVG(medication_complexity_score) AS mean_complexity_score,
  AVG(los_days) AS average_los_days,
  AVG(CAST(hospital_expire_flag AS NUMERIC)) AS in_hospital_mortality_rate,
  AVG(readmitted_30_days) AS readmission_30_day_rate
FROM
  admissions_in_quintiles
GROUP BY
  complexity_quintile
ORDER BY
  complexity_quintile;