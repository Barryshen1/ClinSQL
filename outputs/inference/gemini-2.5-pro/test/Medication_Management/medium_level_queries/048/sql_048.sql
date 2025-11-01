WITH
  diagnosis_cohort AS (
    -- Identify hospital admissions with both a diabetes and a heart failure diagnosis
    SELECT
      hadm_id
    FROM
      (
        SELECT
          hadm_id,
          MAX(
            CASE
              WHEN (icd_version = 9 AND icd_code LIKE '250%') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13')) THEN 1
              ELSE 0
            END
          ) AS has_diabetes,
          MAX(
            CASE
              WHEN (icd_version = 9 AND icd_code LIKE '428%') OR (icd_version = 10 AND icd_code LIKE 'I50%') THEN 1
              ELSE 0
            END
          ) AS has_hf
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        GROUP BY
          hadm_id
      )
    WHERE
      has_diabetes = 1 AND has_hf = 1
  ),
  cohort_hadm AS (
    -- Define the final patient cohort based on age, LOS, and diagnoses
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN
      diagnosis_cohort AS dc ON a.hadm_id = dc.hadm_id
    WHERE
      p.anchor_age BETWEEN 65 AND 75
      AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 96
  ),
  insulin_prescriptions AS (
    -- Categorize all insulin prescriptions
    SELECT
      pr.hadm_id,
      pr.starttime,
      pr.stoptime,
      -- Flag for Basal insulin
      CASE
        WHEN LOWER(pr.drug) LIKE '%glargine%' OR LOWER(pr.drug) LIKE '%lantus%'
        OR LOWER(pr.drug) LIKE '%detemir%' OR LOWER(pr.drug) LIKE '%levemir%'
        OR LOWER(pr.drug) LIKE '%degludec%' OR LOWER(pr.drug) LIKE '%tresiba%'
        OR LOWER(pr.drug) LIKE '%nph%' OR LOWER(pr.drug) LIKE '%humulin n%' OR LOWER(pr.drug) LIKE '%novolin n%' THEN 1
        ELSE 0
      END AS is_basal,
      -- Flag for Bolus insulin
      CASE
        WHEN (
          LOWER(pr.drug) LIKE '%lispro%' OR LOWER(pr.drug) LIKE '%humalog%'
          OR LOWER(pr.drug) LIKE '%aspart%' OR LOWER(pr.drug) LIKE '%novolog%'
          OR LOWER(pr.drug) LIKE '%glulisine%' OR LOWER(pr.drug) LIKE '%apidra%'
          OR LOWER(pr.drug) LIKE '%regular%' OR LOWER(pr.drug) LIKE '%humulin r%' OR LOWER(pr.drug) LIKE '%novolin r%'
        )
        AND NOT (LOWER(pr.drug) LIKE '%70/30%' OR LOWER(pr.drug) LIKE '%75/25%' OR LOWER(pr.drug) LIKE '%50/50%') THEN 1
        ELSE 0
      END AS is_bolus,
      -- Flag for Sliding Scale insulin
      CASE
        WHEN ph.sliding_scale = 'Y' THEN 1
        ELSE 0
      END AS is_sliding_scale
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph ON pr.pharmacy_id = ph.pharmacy_id
    WHERE
      LOWER(pr.drug) LIKE '%insulin%' AND pr.starttime IS NOT NULL
  ),
  patient_regimen_flags AS (
    -- Determine for each patient if they were on a given regimen in the first/final 48 hours
    SELECT
      c.hadm_id,
      -- Flags for the first 48 hours
      MAX(
        CASE
          WHEN i.is_basal = 1 AND i.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND COALESCE(i.stoptime, c.dischtime) >= c.admittime THEN 1
          ELSE 0
        END
      ) AS had_basal_early,
      MAX(
        CASE
          WHEN i.is_bolus = 1 AND i.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND COALESCE(i.stoptime, c.dischtime) >= c.admittime THEN 1
          ELSE 0
        END
      ) AS had_bolus_early,
      MAX(
        CASE
          WHEN i.is_sliding_scale = 1 AND i.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AND COALESCE(i.stoptime, c.dischtime) >= c.admittime THEN 1
          ELSE 0
        END
      ) AS had_ssi_early,
      -- Flags for the final 48 hours
      MAX(
        CASE
          WHEN i.is_basal = 1 AND i.starttime <= c.dischtime AND COALESCE(i.stoptime, c.dischtime) >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) THEN 1
          ELSE 0
        END
      ) AS had_basal_final,
      MAX(
        CASE
          WHEN i.is_bolus = 1 AND i.starttime <= c.dischtime AND COALESCE(i.stoptime, c.dischtime) >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) THEN 1
          ELSE 0
        END
      ) AS had_bolus_final,
      MAX(
        CASE
          WHEN i.is_sliding_scale = 1 AND i.starttime <= c.dischtime AND COALESCE(i.stoptime, c.dischtime) >= DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) THEN 1
          ELSE 0
        END
      ) AS had_ssi_final
    FROM
      cohort_hadm AS c
    LEFT JOIN
      insulin_prescriptions AS i ON c.hadm_id = i.hadm_id
    GROUP BY
      c.hadm_id,
      c.admittime,
      c.dischtime
  ),
  transition_summary AS (
    -- Assign a single, mutually exclusive regimen category to each patient for each window
    SELECT
      hadm_id,
      -- Hierarchical category for early regimen
      CASE
        WHEN had_basal_early = 1 AND had_bolus_early = 1 THEN 'Basal-Bolus'
        WHEN had_basal_early = 1 THEN 'Basal'
        WHEN had_bolus_early = 1 THEN 'Bolus'
        WHEN had_ssi_early = 1 THEN 'Sliding-Scale Only'
        ELSE 'Other/None'
      END AS early_regimen,
      -- Hierarchical category for final regimen
      CASE
        WHEN had_basal_final = 1 AND had_bolus_final = 1 THEN 'Basal-Bolus'
        WHEN had_basal_final = 1 THEN 'Basal'
        WHEN had_bolus_final = 1 THEN 'Bolus'
        WHEN had_ssi_final = 1 THEN 'Sliding-Scale Only'
        ELSE 'Other/None'
      END AS final_regimen
    FROM
      patient_regimen_flags
  )
-- Final output: a transition matrix showing movement between regimen categories
SELECT
  early_regimen,
  final_regimen,
  COUNT(hadm_id) AS number_of_patients
FROM
  transition_summary
GROUP BY
  early_regimen,
  final_regimen
ORDER BY
  early_regimen,
  final_regimen;