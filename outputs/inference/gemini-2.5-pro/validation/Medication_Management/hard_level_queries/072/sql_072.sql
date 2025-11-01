WITH
  -- Step 1: Define the base cohort of female patients aged 84-94 with DKA.
  dka_admissions AS (
    SELECT DISTINCT
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 84 AND 94
      AND (
        -- ICD-9 codes for Diabetic Ketoacidosis
        (dx.icd_version = 9 AND dx.icd_code LIKE '250.1%')
        OR
        -- ICD-10 codes for Diabetic Ketoacidosis
        (
          dx.icd_version = 10 AND (
            dx.icd_code LIKE 'E10.1%' -- Type 1
            OR dx.icd_code LIKE 'E11.1%' -- Type 2
            OR dx.icd_code LIKE 'E13.1%' -- Other specified
          )
        )
      )
  ),
  -- Step 2: Identify hyperkalemia-risk drug classes administered in the first 48h
  meds_first_48h AS (
    SELECT
      dka.hadm_id,
      -- Classify drugs into categories of interest
      CASE
        WHEN LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR LOWER(pr.drug) LIKE '%ramipril%' OR LOWER(pr.drug) LIKE '%captopril%' OR LOWER(pr.drug) LIKE '%benazepril%' OR LOWER(pr.drug) LIKE '%quinapril%'
          THEN 'acei'
        WHEN LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%valsartan%' OR LOWER(pr.drug) LIKE '%irbesartan%' OR LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%olmesartan%'
          THEN 'arb'
        WHEN LOWER(pr.drug) LIKE '%spironolactone%' OR LOWER(pr.drug) LIKE '%eplerenone%' OR LOWER(pr.drug) LIKE '%amiloride%' OR LOWER(pr.drug) LIKE '%triamterene%'
          THEN 'k_sparing'
        WHEN LOWER(pr.drug) LIKE '%ibuprofen%' OR LOWER(pr.drug) LIKE '%naproxen%' OR LOWER(pr.drug) LIKE '%ketorolac%' OR LOWER(pr.drug) LIKE '%diclofenac%' OR LOWER(pr.drug) LIKE '%indomethacin%' OR LOWER(pr.drug) LIKE '%meloxicam%' OR LOWER(pr.drug) LIKE '%celecoxib%'
          THEN 'nsaid'
        WHEN LOWER(pr.drug) LIKE '%trimethoprim%'
          THEN 'trimethoprim'
        WHEN LOWER(pr.drug) LIKE 'potassium%'
          THEN 'k_supplement'
        ELSE NULL
      END AS drug_class
    FROM dka_admissions AS dka
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON dka.hadm_id = pr.hadm_id
    WHERE
      -- Filter for prescriptions started within the first 48 hours of admission
      pr.starttime <= DATETIME_ADD(dka.admittime, INTERVAL 48 HOUR)
  ),
  -- Step 3: Flag patients with interactions based on drug classes
  interaction_flags AS (
    SELECT
      hadm_id,
      -- Create flags for each drug class
      MAX(CASE WHEN drug_class = 'acei' THEN 1 ELSE 0 END) AS has_acei,
      MAX(CASE WHEN drug_class = 'arb' THEN 1 ELSE 0 END) AS has_arb,
      MAX(CASE WHEN drug_class = 'k_sparing' THEN 1 ELSE 0 END) AS has_k_sparing,
      MAX(CASE WHEN drug_class = 'nsaid' THEN 1 ELSE 0 END) AS has_nsaid,
      MAX(CASE WHEN drug_class = 'trimethoprim' THEN 1 ELSE 0 END) AS has_trimethoprim,
      MAX(CASE WHEN drug_class = 'k_supplement' THEN 1 ELSE 0 END) AS has_k_supplement
    FROM meds_first_48h
    WHERE
      drug_class IS NOT NULL
    GROUP BY
      hadm_id
  ),
  -- Step 4: Calculate total medication complexity for each admission
  medication_complexity AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT drug) AS med_complexity_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      hadm_id IN (
        SELECT hadm_id FROM dka_admissions
      )
    GROUP BY
      hadm_id
  ),
  -- Step 5: Combine all features for the final cohort
  cohort_with_features AS (
    SELECT
      dka.hadm_id,
      dka.los,
      dka.hospital_expire_flag,
      COALESCE(mc.med_complexity_count, 0) AS med_complexity,
      -- Define the interaction flag based on co-administration of drug classes
      CASE
        WHEN
          -- (ACEi or ARB) with (K-sparing diuretic, NSAID, or Trimethoprim)
          (
            (COALESCE(i_flags.has_acei, 0) = 1 OR COALESCE(i_flags.has_arb, 0) = 1) AND (COALESCE(i_flags.has_k_sparing, 0) = 1 OR COALESCE(i_flags.has_nsaid, 0) = 1 OR COALESCE(i_flags.has_trimethoprim, 0) = 1)
          )
          -- K-sparing diuretic with Potassium supplement
          OR (COALESCE(i_flags.has_k_sparing, 0) = 1 AND COALESCE(i_flags.has_k_supplement, 0) = 1)
          -- ACEi with ARB
          OR (COALESCE(i_flags.has_acei, 0) = 1 AND COALESCE(i_flags.has_arb, 0) = 1)
          THEN 1
        ELSE 0
      END AS has_interaction,
      PERCENT_RANK() OVER (ORDER BY COALESCE(mc.med_complexity_count, 0)) AS med_complexity_percentile,
      NTILE(4) OVER (ORDER BY COALESCE(mc.med_complexity_count, 0)) AS med_complexity_quartile
    FROM dka_admissions AS dka
    LEFT JOIN
      interaction_flags AS i_flags
      ON dka.hadm_id = i_flags.hadm_id
    LEFT JOIN
      medication_complexity AS mc
      ON dka.hadm_id = mc.hadm_id
  )
-- Final Step: Generate the two requested reports
-- Report 1: Comparison between groups with and without drug interactions
SELECT
  'Comparison by Interaction Group' AS analysis_name,
  CASE
    WHEN has_interaction = 1 THEN 'With Hyperkalemia-Risk Interaction'
    ELSE 'Without Hyperkalemia-Risk Interaction'
  END AS strata,
  COUNT(hadm_id) AS number_of_patients,
  AVG(med_complexity) AS mean_medication_complexity,
  AVG(med_complexity_percentile) AS mean_medication_complexity_percentile,
  AVG(los) AS mean_length_of_stay_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_features
GROUP BY
  analysis_name,
  strata
UNION ALL
-- Report 2: Analysis of the top quartile for medication complexity
SELECT
  'Top Quartile of Medication Complexity' AS analysis_name,
  'Overall' AS strata,
  COUNT(hadm_id) AS number_of_patients,
  NULL AS mean_medication_complexity, -- Not requested for this part
  NULL AS mean_medication_complexity_percentile, -- Not applicable
  AVG(los) AS mean_length_of_stay_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_features
WHERE
  med_complexity_quartile = 4 -- Top quartile
GROUP BY
  analysis_name,
  strata
ORDER BY
  analysis_name,
  strata DESC;