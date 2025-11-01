WITH aki_cohort AS (
  -- Step 1: Identify female inpatients, age 81-91, with an AKI diagnosis
  SELECT DISTINCT
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND (dx.icd_code LIKE 'N17%' OR dx.icd_code LIKE '584%')
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL -- Ensure valid time intervals
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0 -- Exclude invalid LOS
),
med_summary AS (
  -- Step 2: For the cohort, count distinct meds and flag for CNS/nephrotoxic drugs
  SELECT
    pr.hadm_id,
    COUNT(DISTINCT pr.drug) AS medication_complexity,
    -- Flag for CNS-depressant drugs
    MAX(CASE
      WHEN LOWER(pr.drug) LIKE 'morphine%'
        OR LOWER(pr.drug) LIKE 'fentanyl%'
        OR LOWER(pr.drug) LIKE 'hydromorphone%' OR LOWER(pr.drug) LIKE 'dilaudid%'
        OR LOWER(pr.drug) LIKE 'oxycodone%' OR LOWER(pr.drug) LIKE 'percocet%'
        OR LOWER(pr.drug) LIKE 'tramadol%'
        OR LOWER(pr.drug) LIKE 'lorazepam%' OR LOWER(pr.drug) LIKE 'ativan%'
        OR LOWER(pr.drug) LIKE 'diazepam%' OR LOWER(pr.drug) LIKE 'valium%'
        OR LOWER(pr.drug) LIKE 'midazolam%' OR LOWER(pr.drug) LIKE 'versed%'
        OR LOWER(pr.drug) LIKE 'propofol%' OR LOWER(pr.drug) LIKE 'diprivan%'
        OR LOWER(pr.drug) LIKE 'dexmedetomidine%' OR LOWER(pr.drug) LIKE 'precedex%'
        OR LOWER(pr.drug) LIKE 'phenobarbital%'
        OR LOWER(pr.drug) LIKE 'zolpidem%'
        THEN 1 ELSE 0 END) AS has_cns,
    -- Flag for nephrotoxic drugs
    MAX(CASE
      WHEN LOWER(pr.drug) LIKE 'vancomycin%'
        OR LOWER(pr.drug) LIKE 'gentamicin%'
        OR LOWER(pr.drug) LIKE 'tobramycin%'
        OR LOWER(pr.drug) LIKE 'amikacin%'
        OR LOWER(pr.drug) LIKE 'ibuprofen%'
        OR LOWER(pr.drug) LIKE 'naproxen%'
        OR LOWER(pr.drug) LIKE 'ketorolac%' OR LOWER(pr.drug) LIKE 'toradol%'
        OR LOWER(pr.drug) LIKE 'lisinopril%'
        OR LOWER(pr.drug) LIKE 'losartan%'
        OR LOWER(pr.drug) LIKE 'furosemide%' OR LOWER(pr.drug) LIKE 'lasix%'
        THEN 1 ELSE 0 END) AS has_nephrotoxic
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    aki_cohort
    ON pr.hadm_id = aki_cohort.hadm_id
  GROUP BY
    pr.hadm_id
),
final_data AS (
  -- Step 3: Combine cohort with medication data, defining the two comparison groups
  SELECT
    cohort.hadm_id,
    cohort.los,
    cohort.hospital_expire_flag,
    COALESCE(med.medication_complexity, 0) AS medication_complexity,
    CASE
      WHEN COALESCE(med.has_cns, 0) = 1 AND COALESCE(med.has_nephrotoxic, 0) = 1
      THEN 'Both CNS & Nephrotoxic'
      ELSE 'Other AKI'
    END AS patient_group
  FROM
    aki_cohort AS cohort
  LEFT JOIN
    med_summary AS med
    ON cohort.hadm_id = med.hadm_id
),
data_with_los_quartile AS (
  -- Step 4: Rank patients by LOS within each group to identify the top quartile
  SELECT
    *,
    NTILE(4) OVER (PARTITION BY patient_group ORDER BY los DESC) AS los_quartile
  FROM
    final_data
)
-- Step 5: Aggregate all metrics and present the final comparison
SELECT
  patient_group,
  COUNT(hadm_id) AS num_patients,
  AVG(medication_complexity) AS mean_complexity,
  APPROX_QUANTILES(medication_complexity, 4)[OFFSET(1)] AS complexity_q1,
  APPROX_QUANTILES(medication_complexity, 4)[OFFSET(2)] AS complexity_median,
  APPROX_QUANTILES(medication_complexity, 4)[OFFSET(3)] AS complexity_q3,
  AVG(los) AS overall_los,
  AVG(hospital_expire_flag) * 100 AS overall_mortality_percent,
  AVG(CASE WHEN los_quartile = 1 THEN los END) AS top_quartile_los,
  AVG(CASE WHEN los_quartile = 1 THEN hospital_expire_flag END) * 100 AS top_quartile_mortality_percent
FROM
  data_with_los_quartile
GROUP BY
  patient_group
ORDER BY
  patient_group;