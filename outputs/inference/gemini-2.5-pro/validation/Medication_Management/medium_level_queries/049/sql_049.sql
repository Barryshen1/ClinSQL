WITH
  diagnoses AS (
    -- First, identify admissions with diagnoses for both Diabetes and Heart Failure
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN
            (icd_version = 9 AND icd_code LIKE '250%')
            OR (
              icd_version = 10 AND (
                icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%'
                OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
              )
            )
            THEN 1
          ELSE 0
        END
      ) AS has_diabetes,
      MAX(
        CASE
          WHEN (icd_version = 9 AND icd_code LIKE '428%') OR (icd_version = 10 AND icd_code LIKE 'I50%')
            THEN 1
          ELSE 0
        END
      ) AS has_heart_failure
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),

  cohort_admissions AS (
    -- Define the primary cohort based on demographics, diagnoses, and length of stay
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN diagnoses AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      -- Male patients
      pat.gender = 'M'
      -- Age between 66 and 76 at time of admission
      AND (DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age)
      BETWEEN 66 AND 76
      -- Presence of both diagnoses
      AND dx.has_diabetes = 1
      AND dx.has_heart_failure = 1
      -- Hospital stay of at least 72 hours
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
  ),

  antidiabetic_meds AS (
    -- Identify and classify antidiabetic medications for the cohort
    SELECT
      p.hadm_id,
      p.starttime,
      -- Classification of antidiabetic drugs using common names
      CASE
        WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%humalog%' OR LOWER(p.drug) LIKE '%novolog%'
          OR LOWER(p.drug) LIKE '%lantus%' OR LOWER(p.drug) LIKE '%levemir%' OR LOWER(p.drug) LIKE '%glargine%'
          OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%'
          THEN 'Insulin'
        WHEN LOWER(p.drug) LIKE '%metformin%'
          THEN 'Biguanides'
        WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%'
          THEN 'Sulfonylureas'
        WHEN
          LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%januvia%' OR LOWER(p.drug) LIKE '%saxagliptin%'
          OR LOWER(p.drug) LIKE '%onglyza%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%tradjenta%'
          THEN 'DPP-4 Inhibitors'
        WHEN
          LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%jardiance%'
          OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%farxiga%'
          OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%invokana%'
          THEN 'SGLT-2 Inhibitors'
        WHEN
          LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%actos%' OR LOWER(p.drug) LIKE '%rosiglitazone%'
          OR LOWER(p.drug) LIKE '%avandia%'
          THEN 'Thiazolidinediones (TZDs)'
        WHEN
          LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%victoza%' OR LOWER(p.drug) LIKE '%semaglutide%'
          OR LOWER(p.drug) LIKE '%ozempic%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%bydureon%'
          OR LOWER(p.drug) LIKE '%byetta%'
          THEN 'GLP-1 Agonists'
        ELSE NULL
      END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    INNER JOIN cohort_admissions AS c
      ON p.hadm_id = c.hadm_id
  ),

  total_cohort_count AS (
    -- Calculate the total number of unique admissions in the cohort for the denominator
    SELECT
      COUNT(DISTINCT hadm_id) AS total_admissions
    FROM cohort_admissions
  ),

  timed_meds AS (
    -- Associate medications with time windows (first 72h, final 24h)
    SELECT
      meds.hadm_id,
      meds.drug_class,
      (
        meds.starttime >= cohort.admittime AND meds.starttime < DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR)
      ) AS in_first_72h,
      (
        meds.starttime >= DATETIME_SUB(cohort.dischtime, INTERVAL 24 HOUR) AND meds.starttime <= cohort.dischtime
      ) AS in_final_24h
    FROM antidiabetic_meds AS meds
    INNER JOIN cohort_admissions AS cohort
      ON meds.hadm_id = cohort.hadm_id
    WHERE
      meds.drug_class IS NOT NULL
  )

-- Final aggregation to calculate percentages
SELECT
  tm.drug_class,
  -- Percentage of admissions receiving the drug class in the first 72h
  ROUND(
    100.0 * COUNT(DISTINCT CASE WHEN tm.in_first_72h THEN tm.hadm_id END)
    / (
      SELECT
        total_admissions
      FROM total_cohort_count
    ),
    2
  ) AS percentage_in_first_72h,
  -- Percentage of admissions receiving the drug class in the final 24h
  ROUND(
    100.0 * COUNT(DISTINCT CASE WHEN tm.in_final_24h THEN tm.hadm_id END)
    / (
      SELECT
        total_admissions
      FROM total_cohort_count
    ),
    2
  ) AS percentage_in_final_24h
FROM timed_meds AS tm
GROUP BY
  tm.drug_class
ORDER BY
  tm.drug_class;