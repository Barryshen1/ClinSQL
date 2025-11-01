WITH
-- Step 1: Identify the hospital admission IDs for the patient cohort.
-- Cohort: Female patients, aged 78-88 at admission, with a diagnosis of acute ischemic stroke.
cohort_hadm_ids AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 78 AND 88
    AND (
      -- ICD-9 codes for acute ischemic stroke (cerebral artery occlusion with cerebral infarction)
      dx.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '43491')
      -- ICD-10 codes for ischemic stroke
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I63%')
    )
),

-- Step 2: For each admission, count the number of critical lab events within the first 72 hours.
-- A critical lab event is a numeric value outside its defined normal reference range.
critical_events_by_admission AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS num_critical_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON le.hadm_id = adm.hadm_id
  WHERE
    le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY
    le.hadm_id
),

-- Step 3: Create a comprehensive table of all admissions with their associated 72-hour critical lab event count.
-- This serves as the base for calculating statistics for both the cohort and the general inpatient population.
all_admissions_with_scores AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    COALESCE(ce.num_critical_events, 0) AS critical_lab_events_72hr
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  LEFT JOIN critical_events_by_admission AS ce
    ON adm.hadm_id = ce.hadm_id
),

-- Step 4: Calculate all statistics for the specific cohort.
cohort_stats AS (
  SELECT
    MIN(a.critical_lab_events_72hr) AS cohort_min_instability_score,
    AVG(a.critical_lab_events_72hr) AS cohort_avg_critical_events,
    AVG(a.los_days) AS cohort_avg_los_days,
    AVG(a.hospital_expire_flag) * 100 AS cohort_in_hospital_mortality_percent
  FROM all_admissions_with_scores AS a
  WHERE a.hadm_id IN (SELECT hadm_id FROM cohort_hadm_ids)
),

-- Step 5: Calculate the average critical lab events for the general inpatient population.
general_population_stats AS (
  SELECT
    AVG(critical_lab_events_72hr) AS general_avg_critical_events
  FROM all_admissions_with_scores
)

-- Step 6: Combine the results into a single output row.
SELECT
  cs.cohort_min_instability_score,
  cs.cohort_avg_critical_events,
  gps.general_avg_critical_events,
  cs.cohort_avg_los_days,
  cs.cohort_in_hospital_mortality_percent
FROM cohort_stats AS cs, general_population_stats AS gps;