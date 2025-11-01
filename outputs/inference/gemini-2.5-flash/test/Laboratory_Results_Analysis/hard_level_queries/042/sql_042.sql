with Intracerebral Hemorrhage (ICH).
-- It computes a 48-hour instability score (count of abnormal lab types),
-- stratifies patients into quartiles based on this score,
-- reports the count, mean Length of Stay (LOS), and mortality per quartile,
-- and compares these critical rates to all inpatients (with instability scores).
WITH admission_details AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
),
-- Step 2: Identify all abnormal lab events (distinct itemids) within the first 48 hours of admission
abnormal_labs_48hr AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN
    admission_details adm_det
    ON le.subject_id = adm_det.subject_id AND le.hadm_id = adm_det.hadm_id
  WHERE
    le.charttime BETWEEN adm_det.admittime AND TIMESTAMP_ADD(adm_det.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL -- Ensure numeric value exists
    AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL -- Ensure reference ranges exist
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper) -- Check for abnormality
),
-- Step 3: Calculate the 48-hour instability score (count of distinct abnormal lab types) for each admission
instability_scores AS (
  SELECT
    adm_det.subject_id,
    adm_det.hadm_id,
    adm_det.admittime,
    adm_det.dischtime,
    adm_det.hospital_expire_flag,
    adm_det.gender,
    adm_det.anchor_age,
    adm_det.los_days,
    -- Count distinct abnormal lab itemids; COALESCE handles admissions with no abnormal labs as 0 score
    COALESCE(COUNT(DISTINCT ab_lab.itemid), 0) AS instability_score
  FROM
    admission_details adm_det
  LEFT JOIN -- Use LEFT JOIN to include all admissions, even those with 0 abnormal labs
    abnormal_labs_48hr ab_lab
    ON adm_det.subject_id = ab_lab.subject_id AND adm_det.hadm_id = ab_lab.hadm_id
  GROUP BY
    adm_det.subject_id,
    adm_det.hadm_id,
    adm_det.admittime,
    adm_det.dischtime,
    adm_det.hospital_expire_flag,
    adm_det.gender,
    adm_det.anchor_age,
    adm_det.los_days
),
-- Step 4: Identify the specific ICH cohort: male, 73-83 years old, with ICH diagnosis
ich_cohort AS (
  SELECT
    iss.*
  FROM
    instability_scores iss
  WHERE
    iss.gender = 'M'
    AND iss.anchor_age BETWEEN 73 AND 83 -- Age range for the cohort
    AND iss.hadm_id IN ( -- Filter for admissions with ICH diagnosis
      SELECT
        DISTINCT hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code = '431') -- ICD-9 for Intracerebral hemorrhage
        OR (icd_version = 10 AND icd_code LIKE 'I61%') -- ICD-10 for Nontraumatic intracerebral hemorrhage (various specific codes)
    )
),
-- Step 5: Assign instability score quartiles for the identified ICH cohort
ich_cohort_with_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM
    ich_cohort
),
-- Step 6: Calculate overall statistics for the ICH cohort for comparison
ich_cohort_overall_stats AS (
  SELECT
    'ICH Cohort Overall' AS group_name,
    COUNT(hadm_id) AS patient_count,
    AVG(los_days) AS mean_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
    AVG(instability_score) AS mean_instability_score
  FROM
    ich_cohort
),
-- Step 7: Calculate overall statistics for all admissions to serve as a general inpatient comparison
all_admissions_overall_stats AS (
  SELECT
    'All Admissions (with score)' AS group_name,
    COUNT(hadm_id) AS patient_count,
    AVG(los_days) AS mean_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
    AVG(instability_score) AS mean_instability_score
  FROM
    instability_scores
)
-- Final SELECT statements:
-- Part 1: Report count, mean LOS, and mortality per quartile for the ICH cohort
SELECT
  'ICH Cohort Quartile Breakdown' AS analysis_type,
  CAST(instability_quartile AS STRING) AS category,
  COUNT(hadm_id) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
  ROUND(MIN(instability_score), 0) AS min_score_in_quartile,
  ROUND(MAX(instability_score), 0) AS max_score_in_quartile,
  ROUND(AVG(instability_score), 2) AS avg_score_in_quartile
FROM
  ich_cohort_with_quartile
GROUP BY
  instability_quartile
ORDER BY
  instability_quartile

UNION ALL

-- Part 2: Compare overall critical rates (mean LOS, mortality, mean instability score)
-- between the ICH cohort and all admissions with an instability score
SELECT
  'Overall Comparison' AS analysis_type,
  group_name AS category,
  patient_count,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_rate_percent, 2) AS mortality_rate_percent,
  NULL AS min_score_in_quartile, -- Not applicable for overall summary
  NULL AS max_score_in_quartile, -- Not applicable for overall summary
  ROUND(mean_instability_score, 2) AS avg_score_in_quartile
FROM
  ich_cohort_overall_stats

UNION ALL

SELECT
  'Overall Comparison' AS analysis_type,
  group_name AS category,
  patient_count,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_rate_percent, 2) AS mortality_rate_percent,
  NULL AS min_score_in_quartile,
  NULL AS max_score_in_quartile,
  ROUND(mean_instability_score, 2) AS avg_score_in_quartile
FROM
  all_admissions_overall_stats;