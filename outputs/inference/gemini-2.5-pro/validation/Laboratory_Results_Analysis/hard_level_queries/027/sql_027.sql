with a diagnosis of lower GI bleeding. It calculates a "lab instability score"
-- based on the count of distinct abnormal lab tests in the first 72 hours of admission.
-- Patients are then stratified into quintiles based on this score.
-- The final output compares length of stay, mortality, and the average number of critical labs
-- across these quintiles, benchmarking the critical lab rate against the general inpatient population.

WITH
-- 1. Identify ICD codes related to lower GI bleeding
diag_gi_bleed AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    LOWER(long_title) LIKE '%lower gastrointestinal bleed%' OR
    LOWER(long_title) LIKE '%hemorrhage of rectum and anus%' OR
    LOWER(long_title) LIKE '%melena%' OR
    LOWER(long_title) LIKE '%hematochezia%'
),

-- 2. Define the patient cohort: Male, 89-99 years old, with a lower GI bleed diagnosis
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  INNER JOIN diag_gi_bleed AS dgb
    ON dx.icd_code = dgb.icd_code AND dx.icd_version = dgb.icd_version
  WHERE
    p.gender = 'M'
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 89 AND 99)
),

-- 3. Calculate lab scores for the cohort within the first 72 hours of admission
lab_scores AS (
  SELECT
    c.hadm_id,
    -- "Lab instability score": count of distinct abnormal lab tests
    COUNT(DISTINCT le.itemid) AS lab_instability_score,
    -- Total count of all abnormal labs for rate calculation
    COUNT(le.labevent_id) AS total_critical_labs
  FROM cohort AS c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON c.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY c.hadm_id
),

-- 4. Join scores back to cohort, calculate LOS, and assign quintiles
cohort_with_scores AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los,
    COALESCE(ls.lab_instability_score, 0) AS lab_instability_score,
    COALESCE(ls.total_critical_labs, 0) AS total_critical_labs,
    -- Stratify the cohort into 5 groups based on the instability score
    NTILE(5) OVER (ORDER BY COALESCE(ls.lab_instability_score, 0)) AS score_quintile
  FROM cohort AS c
  LEFT JOIN lab_scores AS ls
    ON c.hadm_id = ls.hadm_id
),

-- 5. Calculate statistics for each quintile
quintile_stats AS (
  SELECT
    score_quintile,
    COUNT(hadm_id) AS num_patients,
    MIN(lab_instability_score) AS min_instability_score,
    MAX(lab_instability_score) AS max_instability_score,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    -- "Quintile critical-lab rate": avg number of critical labs per patient in the quintile
    AVG(total_critical_labs) AS cohort_critical_lab_rate
  FROM cohort_with_scores
  GROUP BY score_quintile
),

-- 6. Calculate the baseline critical lab rate for the general inpatient population
general_inpatient_baseline AS (
  SELECT
    -- Total abnormal labs in first 72h / total number of admissions
    SAFE_DIVIDE(
      COUNT(CASE WHEN le.flag = 'abnormal' THEN le.labevent_id ELSE NULL END),
      COUNT(DISTINCT a.hadm_id)
    ) AS general_critical_lab_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
)

-- 7. Final result: Combine quintile stats with the general baseline for comparison
SELECT
  qs.score_quintile,
  qs.num_patients,
  qs.min_instability_score,
  qs.max_instability_score,
  ROUND(qs.avg_los, 1) AS avg_los_days,
  ROUND(qs.mortality_rate, 3) AS mortality_rate,
  ROUND(qs.cohort_critical_lab_rate, 2) AS cohort_critical_lab_rate,
  ROUND(gb.general_critical_lab_rate, 2) AS general_critical_lab_rate
FROM quintile_stats AS qs
CROSS JOIN general_inpatient_baseline AS gb
ORDER BY qs.score_quintile;