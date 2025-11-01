with ACS and an ICU stay, what are mean risk score and 30‑day mortality?
-- Compare cardiac and neurologic complication rates and survivor mean LOS to age‑matched general inpatients, and report matched-profile percentile.
-- This query identifies female patients aged 67-77 with Acute Coronary Syndrome (ACS) and an ICU stay,
-- and compares their outcomes to an age-matched general inpatient control group.
-- It calculates mortality, complication rates, LOS, and a corrected first-day SOFA score for the ACS cohort.

WITH
  -- Step 1: Define the base cohort of female patients aged 67-77
  patient_base AS (
    SELECT
      p.subject_id,
      p.anchor_age,
      p.dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77
  ),
  -- Step 2: Define ICD codes for ACS and complications
  acs_codes AS (
    SELECT '410' AS code, 9 AS version UNION ALL SELECT '411', 9 UNION ALL SELECT 'I20', 10 UNION ALL SELECT 'I21', 10 UNION ALL SELECT 'I22', 10 UNION ALL SELECT 'I24', 10
  ),
  cardiac_comp_codes AS (
    SELECT '785.51' AS code, 9 AS version UNION ALL SELECT 'R57.0', 10 UNION ALL SELECT '427.5', 9 UNION ALL SELECT 'I46', 10 UNION ALL SELECT '427.41', 9 UNION ALL SELECT 'I49.01', 10 UNION ALL SELECT '428.0', 9 UNION ALL SELECT '428.1', 9 UNION ALL SELECT 'I50', 10
  ),
  neuro_comp_codes AS (
    SELECT '430' AS code, 9 AS version UNION ALL SELECT '431', 9 UNION ALL SELECT '433', 9 UNION ALL SELECT '434', 9 UNION ALL SELECT 'I60', 10 UNION ALL SELECT 'I61', 10 UNION ALL SELECT 'I62', 10 UNION ALL SELECT 'I63', 10 UNION ALL SELECT '780.39', 9 UNION ALL SELECT 'R56.9', 10 UNION ALL SELECT '348.30', 9 UNION ALL SELECT 'G93.40', 10
  ),
  -- Step 3: Identify hospital admissions for the ACS cohort (with ICU) and Control cohort
  hadm_acs AS (
    SELECT DISTINCT a.hadm_id, p.subject_id
    FROM patient_base AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON a.hadm_id = dx.hadm_id
    INNER JOIN acs_codes AS acs ON dx.icd_version = acs.version AND STARTS_WITH(dx.icd_code, acs.code)
    WHERE EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id)
  ),
  cohorts AS (
    -- ACS Cohort
    SELECT h.hadm_id, h.subject_id, 'ACS_ICU' AS cohort_group FROM hadm_acs AS h
    UNION ALL
    -- Control Cohort (age-matched general inpatients, excluding ACS)
    SELECT DISTINCT a.hadm_id, p.subject_id, 'General_Inpatient' AS cohort_group
    FROM patient_base AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    WHERE a.hadm_id NOT IN (SELECT hadm_id FROM hadm_acs)
  ),
  -- Pre-calculate admissions with complications for efficiency
  hadm_with_cardiac_comp AS (
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    INNER JOIN cardiac_comp_codes cc ON dx.icd_version = cc.version AND STARTS_WITH(dx.icd_code, cc.code)
  ),
  hadm_with_neuro_comp AS (
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    INNER JOIN neuro_comp_codes nc ON dx.icd_version = nc.version AND STARTS_WITH(dx.icd_code, nc.code)
  ),
  -- Step 4: Calculate mortality, LOS, and find complication flags
  outcomes AS (
    SELECT
      c.hadm_id,
      c.cohort_group,
      (CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(CAST(p.dod AS DATE), CAST(adm.admittime AS DATE), DAY) <= 30 THEN 1 ELSE 0 END) AS thirty_day_mortality,
      (CASE WHEN p.dod IS NULL OR DATE_DIFF(CAST(p.dod AS DATE), CAST(adm.admittime AS DATE), DAY) > 30 THEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 ELSE NULL END) AS survivor_los_days,
      (CASE WHEN hcc.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_cardiac_comp,
      (CASE WHEN hnc.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_neuro_comp
    FROM cohorts AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON c.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON c.subject_id = p.subject_id
    LEFT JOIN hadm_with_cardiac_comp AS hcc ON c.hadm_id = hcc.hadm_id
    LEFT JOIN hadm_with_neuro_comp AS hnc ON c.hadm_id = hnc.hadm_id
  ),
  -- Step 5: Calculate SOFA score for the ACS cohort on the first day of their ICU stay
  sofa_components AS (
    SELECT
      icu.stay_id,
      MIN(CASE WHEN labs.itemid = 51265 THEN labs.valuenum END) AS platelets_min,
      MAX(CASE WHEN labs.itemid = 50885 THEN labs.valuenum END) AS bilirubin_max,
      MAX(CASE WHEN labs.itemid = 50912 THEN labs.valuenum END) AS creatinine_max,
      MIN(CASE WHEN labs.itemid = 50821 THEN labs.valuenum END) AS pao2_min,
      -- FiO2 is often charted as a percentage, ensure it's handled correctly.
      MAX(CASE WHEN ce.itemid = 223835 THEN ce.valuenum END) AS fio2_max,
      MIN(CASE WHEN ce.itemid IN (220052, 220181, 225312) THEN ce.valuenum END) AS map_min,
      MIN(gcs.gcs_total) AS gcs_min,
      MAX(CASE WHEN ie.itemid = 221906 THEN ie.rate END) AS norepinephrine_max,
      MAX(CASE WHEN ie.itemid = 221289 THEN ie.rate END) AS epinephrine_max,
      MAX(CASE WHEN ie.itemid = 221662 THEN ie.rate END) AS dopamine_max,
      MAX(CASE WHEN ie.itemid = 221653 THEN ie.rate END) AS dobutamine_max
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN hadm_acs AS c ON icu.hadm_id = c.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS labs ON icu.hadm_id = labs.hadm_id AND labs.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 1 DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON icu.stay_id = ce.stay_id AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 1 DAY)
    LEFT JOIN (
      -- GCS calculation: sum components, if all are present
      SELECT stay_id, charttime,
        (MAX(CASE WHEN itemid = 223901 THEN valuenum END) + MAX(CASE WHEN itemid = 223900 THEN valuenum END) + MAX(CASE WHEN itemid = 220739 THEN valuenum END)) AS gcs_total
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` WHERE itemid IN (223901, 223900, 220739)
      GROUP BY stay_id, charttime
    ) AS gcs ON icu.stay_id = gcs.stay_id AND gcs.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 1 DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie ON icu.stay_id = ie.stay_id AND ie.starttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 1 DAY) AND ie.itemid IN (221906, 221289, 221662, 221653)
    GROUP BY icu.stay_id
  ),
  sofa_scores AS (
    SELECT
      stay_id,
      (CASE WHEN pao2_min IS NULL OR fio2_max IS NULL OR fio2_max = 0 THEN 0 WHEN pao2_min / (fio2_max / 100.0) < 100 THEN 4 WHEN pao2_min / (fio2_max / 100.0) < 200 THEN 3 WHEN pao2_min / (fio2_max / 100.0) < 300 THEN 2 WHEN pao2_min / (fio2_max / 100.0) < 400 THEN 1 ELSE 0 END) -- Respiratory
      + (CASE WHEN platelets_min IS NULL THEN 0 WHEN platelets_min < 20 THEN 4 WHEN platelets_min < 50 THEN 3 WHEN platelets_min < 100 THEN 2 WHEN platelets_min < 150 THEN 1 ELSE 0 END) -- Coagulation
      + (CASE WHEN bilirubin_max IS NULL THEN 0 WHEN bilirubin_max >= 12.0 THEN 4 WHEN bilirubin_max >= 6.0 THEN 3 WHEN bilirubin_max >= 2.0 THEN 2 WHEN bilirubin_max >= 1.2 THEN 1 ELSE 0 END) -- Liver
      + (CASE -- Cardiovascular
          WHEN COALESCE(dopamine_max, 0) > 15 OR COALESCE(epinephrine_max, 0) > 0.1 OR COALESCE(norepinephrine_max, 0) > 0.1 THEN 4
          WHEN COALESCE(dopamine_max, 0) > 5 OR (COALESCE(epinephrine_max, 0) > 0 AND COALESCE(epinephrine_max, 0) <= 0.1) OR (COALESCE(norepinephrine_max, 0) > 0 AND COALESCE(norepinephrine_max, 0) <= 0.1) THEN 3
          WHEN COALESCE(dopamine_max, 0) > 0 OR COALESCE(dobutamine_max, 0) > 0 THEN 2
          WHEN map_min < 70 THEN 1
          ELSE 0 END)
      + (CASE WHEN gcs_min IS NULL THEN 0 WHEN gcs_min <= 6 THEN 4 WHEN gcs_min <= 9 THEN 3 WHEN gcs_min <= 12 THEN 2 WHEN gcs_min <= 14 THEN 1 ELSE 0 END) -- CNS
      + (CASE WHEN creatinine_max IS NULL THEN 0 WHEN creatinine_max >= 5.0 THEN 4 WHEN creatinine_max >= 3.5 THEN 3 WHEN creatinine_max >= 2.0 THEN 2 WHEN creatinine_max >= 1.2 THEN 1 ELSE 0 END) -- Renal
      AS sofa_score
    FROM sofa_components
  ),
  -- Step 6: Aggregate statistics for each cohort
  aggregated_stats AS (
    SELECT cohort_group, COUNT(hadm_id) AS num_patients, AVG(thirty_day_mortality) AS mean_30d_mortality, AVG(survivor_los_days) AS mean_survivor_los, AVG(has_cardiac_comp) AS cardiac_comp_rate, AVG(has_neuro_comp) AS neuro_comp_rate
    FROM outcomes GROUP BY cohort_group
  ),
  -- Step 7: Calculate SOFA analysis for ACS cohort
  acs_sofa_analysis AS (
    SELECT
      AVG(sofa_score) AS mean_sofa_score,
      SAFE_DIVIDE(COUNTIF(sofa_score < (SELECT AVG(sofa_score) FROM sofa_scores)), COUNT(sofa_score)) AS percentile_of_mean_score
    FROM sofa_scores
  )
-- Final Step: Present the results in a readable format
SELECT 'Number of Patients' AS metric, CAST(acs.num_patients AS STRING) AS acs_icu_cohort, CAST(gen.num_patients AS STRING) AS general_inpatient_cohort
FROM aggregated_stats acs, aggregated_stats gen WHERE acs.cohort_group = 'ACS_ICU' AND gen.cohort_group = 'General_Inpatient'
UNION ALL
SELECT 'Mean 30-Day Mortality', FORMAT('%.3f', acs.mean_30d_mortality), FORMAT('%.3f', gen.mean_30d_mortality)
FROM aggregated_stats acs, aggregated_stats gen WHERE acs.cohort_group = 'ACS_ICU' AND gen.cohort_group = 'General_Inpatient'
UNION ALL
SELECT 'Cardiac Complication Rate', FORMAT('%.3f', acs.cardiac_comp_rate), FORMAT('%.3f', gen.cardiac_comp_rate)
FROM aggregated_stats acs, aggregated_stats gen WHERE acs.cohort_group = 'ACS_ICU' AND gen.cohort_group = 'General_Inpatient'
UNION ALL
SELECT 'Neurologic Complication Rate', FORMAT('%.3f', acs.neuro_comp_rate), FORMAT('%.3f', gen.neuro_comp_rate)
FROM aggregated_stats acs, aggregated_stats gen WHERE acs.cohort_group = 'ACS_ICU' AND gen.cohort_group = 'General_Inpatient'
UNION ALL
SELECT 'Mean Survivor LOS (Days)', FORMAT('%.2f', acs.mean_survivor_los), FORMAT('%.2f', gen.mean_survivor_los)
FROM aggregated_stats acs, aggregated_stats gen WHERE acs.cohort_group = 'ACS_ICU' AND gen.cohort_group = 'General_Inpatient'
UNION ALL
SELECT 'Mean First Day SOFA Score', FORMAT('%.2f', asa.mean_sofa_score), 'N/A' FROM acs_sofa_analysis asa
UNION ALL
SELECT 'Matched-Profile Percentile (of mean SOFA)', FORMAT('%.3f', asa.percentile_of_mean_score), 'N/A' FROM acs_sofa_analysis asa;