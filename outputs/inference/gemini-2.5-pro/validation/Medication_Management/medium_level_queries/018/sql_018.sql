WITH
  cohort_hadms AS (
    -- Step 1: Identify the cohort of female inpatients, aged 81-91, with T2DM and Heart Failure.
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'F'
      AND (
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age
      ) BETWEEN 81 AND 91
    GROUP BY
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    HAVING
      -- Check for at least one T2DM diagnosis code
      COUNT(DISTINCT CASE
          WHEN (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'E11')
            OR (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '250' AND SUBSTR(d.icd_code, 5, 1) IN ('0', '2'))
          THEN d.icd_code
        END) > 0
      -- Check for at least one Heart Failure diagnosis code
      AND COUNT(DISTINCT CASE
          WHEN (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'I50')
            OR (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) = '428')
          THEN d.icd_code
        END) > 0
  ),
  medication_events AS (
    -- Step 2: Flag oral antidiabetic prescriptions for the cohort
    SELECT
      pres.hadm_id,
      pres.starttime,
      CASE WHEN LOWER(pres.drug) LIKE '%metformin%'
        THEN 1 ELSE 0 END AS is_metformin,
      CASE
        WHEN
          LOWER(pres.drug) LIKE '%glipizide%' OR LOWER(pres.drug) LIKE '%glyburide%' OR LOWER(pres.drug) LIKE '%glimepiride%'
        THEN 1 ELSE 0 END AS is_sulfonylurea,
      CASE
        WHEN
          LOWER(pres.drug) LIKE '%sitagliptin%' OR LOWER(pres.drug) LIKE '%saxagliptin%' OR LOWER(pres.drug) LIKE '%linagliptin%' OR LOWER(pres.drug) LIKE '%alogliptin%'
        THEN 1 ELSE 0 END AS is_dpp4,
      CASE
        WHEN
          LOWER(pres.drug) LIKE '%canagliflozin%' OR LOWER(pres.drug) LIKE '%dapagliflozin%' OR LOWER(pres.drug) LIKE '%empagliflozin%' OR LOWER(pres.drug) LIKE '%ertugliflozin%'
        THEN 1 ELSE 0 END AS is_sglt2,
      CASE
        WHEN
          LOWER(pres.drug) LIKE '%pioglitazone%' OR LOWER(pres.drug) LIKE '%rosiglitazone%'
        THEN 1 ELSE 0 END AS is_tzd
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    WHERE
      pres.hadm_id IN (SELECT hadm_id FROM cohort_hadms)
      AND pres.route IN ('PO', 'PO/NG') -- Filter for oral routes
  ),
  unpivoted_meds AS (
    -- Step 3: Unpivot the data to have one row per drug class per prescription event
    SELECT
      hadm_id, starttime, 'Metformin' AS drug_class
    FROM medication_events
    WHERE is_metformin = 1
    UNION ALL
    SELECT
      hadm_id, starttime, 'Sulfonylurea' AS drug_class
    FROM medication_events
    WHERE is_sulfonylurea = 1
    UNION ALL
    SELECT
      hadm_id, starttime, 'DPP4 Inhibitor' AS drug_class
    FROM medication_events
    WHERE is_dpp4 = 1
    UNION ALL
    SELECT
      hadm_id, starttime, 'SGLT2 Inhibitor' AS drug_class
    FROM medication_events
    WHERE is_sglt2 = 1
    UNION ALL
    SELECT
      hadm_id, starttime, 'TZD' AS drug_class
    FROM medication_events
    WHERE is_tzd = 1
  ),
  patient_exposure AS (
    -- Step 4: Determine if a patient received a drug class in each window
    SELECT
      um.hadm_id,
      um.drug_class,
      MAX(CASE WHEN um.starttime BETWEEN ch.admittime AND DATETIME_ADD(ch.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS given_in_first_72h,
      MAX(CASE WHEN um.starttime BETWEEN DATETIME_SUB(ch.dischtime, INTERVAL 48 HOUR) AND ch.dischtime THEN 1 ELSE 0 END) AS given_in_final_48h
    FROM
      unpivoted_meds AS um
    INNER JOIN
      cohort_hadms AS ch
      ON um.hadm_id = ch.hadm_id
    GROUP BY
      um.hadm_id,
      um.drug_class
  ),
  patient_counts AS (
    -- Step 5a: Count patients per drug class in each window
    SELECT
      drug_class,
      SUM(given_in_first_72h) AS count_first_72h,
      SUM(given_in_final_48h) AS count_final_48h
    FROM
      patient_exposure
    GROUP BY
      drug_class
  ),
  total_cohort_count AS (
    -- Step 5b: Count total patients in the cohort
    SELECT
      COUNT(DISTINCT hadm_id) AS total_patients
    FROM
      cohort_hadms
  )
-- Final Step: Calculate prevalence and percentage point difference
SELECT
  pc.drug_class,
  ROUND(100.0 * pc.count_first_72h / tcc.total_patients, 2) AS prevalence_first_72h_pct,
  ROUND(100.0 * pc.count_final_48h / tcc.total_patients, 2) AS prevalence_final_48h_pct,
  ROUND(
    (100.0 * pc.count_first_72h / tcc.total_patients) - (100.0 * pc.count_final_48h / tcc.total_patients),
    2
  ) AS absolute_pp_difference
FROM
  patient_counts AS pc
CROSS JOIN
  total_cohort_count AS tcc
ORDER BY
  pc.drug_class;