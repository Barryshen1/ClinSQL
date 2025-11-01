WITH
-- Create a base table with ICU stay details, patient demographics, and hospital outcomes
icu_details AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    pat.gender,
    -- Calculate patient's age at the time of ICU admission
    (pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) AS age_at_icustay,
    -- Flag the first ICU stay for each patient using a window function
    (ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime ASC) = 1) AS is_first_stay,
    adm.hospital_expire_flag,
    -- Calculate hospital length of stay in days for better precision
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
),
-- Identify all hospital admissions with a diagnosis code for ARDS
ards_hadms AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND icd_code = 'J80') -- ICD-10 for Acute respiratory distress syndrome
    OR (icd_version = 9 AND icd_code = '51882') -- ICD-9 for Other pulmonary insufficiency, a common proxy for ARDS
),
-- Count the number of distinct procedures performed in the first 72 hours of each ICU stay
proc_counts AS (
  SELECT
    icu.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_distinct_procedures_72h
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON icu.stay_id = pe.stay_id
  WHERE
    -- Filter procedures to the first 72 hours of the ICU stay
    pe.starttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.stay_id
),
-- Combine all the prepared data into a single analytical table per ICU stay
patient_stats AS (
  SELECT
    icu_d.stay_id,
    icu_d.is_first_stay,
    icu_d.gender,
    icu_d.age_at_icustay,
    icu_d.hospital_los_days,
    icu_d.hospital_expire_flag,
    (ards.hadm_id IS NOT NULL) AS has_ards,
    COALESCE(pc.num_distinct_procedures_72h, 0) AS num_distinct_procedures_72h
  FROM
    icu_details AS icu_d
  LEFT JOIN
    ards_hadms AS ards
    ON icu_d.hadm_id = ards.hadm_id
  LEFT JOIN
    proc_counts AS pc
    ON icu_d.stay_id = pc.stay_id
)
-- Aggregate stats for the target cohort: Female, 37-47, ARDS, First ICU Stay
SELECT
  'Female, 37-47, ARDS, First ICU Stay' AS cohort,
  MIN(num_distinct_procedures_72h) AS min_distinct_procedures_72h,
  APPROX_QUANTILES(num_distinct_procedures_72h, 100)[OFFSET(75)] AS p75_distinct_procedures_72h,
  APPROX_QUANTILES(num_distinct_procedures_72h, 100)[OFFSET(90)] AS p90_distinct_procedures_72h,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS NUMERIC)) * 100 AS in_hospital_mortality_pct
FROM
  patient_stats
WHERE
  is_first_stay = TRUE
  AND gender = 'F'
  AND age_at_icustay BETWEEN 37 AND 47
  AND has_ards = TRUE
UNION ALL
-- Aggregate stats for the comparison cohort: All ICU Patients
SELECT
  'All ICU Patients' AS cohort,
  MIN(num_distinct_procedures_72h) AS min_distinct_procedures_72h,
  APPROX_QUANTILES(num_distinct_procedures_72h, 100)[OFFSET(75)] AS p75_distinct_procedures_72h,
  APPROX_QUANTILES(num_distinct_procedures_72h, 100)[OFFSET(90)] AS p90_distinct_procedures_72h,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS NUMERIC)) * 100 AS in_hospital_mortality_pct
FROM
  patient_stats;