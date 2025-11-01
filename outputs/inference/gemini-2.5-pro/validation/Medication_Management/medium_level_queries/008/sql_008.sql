WITH cohort AS (
  -- Step 1: Define the patient cohort based on demographics and diagnoses
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 44 AND 54
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      GROUP BY hadm_id
      HAVING
        -- T2DM: ICD-10 starts with E11; ICD-9 starts with 250 and 5th digit is 0 or 2 for Type II
        SUM(CASE
          WHEN icd_version = 10 AND icd_code LIKE 'E11%' THEN 1
          WHEN icd_version = 9 AND icd_code LIKE '250%' AND SUBSTR(icd_code, 5, 1) IN ('0', '2') THEN 1
          ELSE 0
        END) > 0
        AND
        -- Heart Failure: ICD-10 starts with I50; ICD-9 starts with 428
        SUM(CASE
          WHEN icd_version = 10 AND icd_code LIKE 'I50%' THEN 1
          WHEN icd_version = 9 AND icd_code LIKE '428%' THEN 1
          ELSE 0
        END) > 0
    )
),
med_admin AS (
  -- Step 2: Identify relevant medication administrations for the cohort
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    e.charttime,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%'
        THEN 'Insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%'
        OR LOWER(e.medication) LIKE '%glipizide%'
        OR LOWER(e.medication) LIKE '%glyburide%'
        OR LOWER(e.medication) LIKE '%glimepiride%'
        OR LOWER(e.medication) LIKE '%pioglitazone%'
        OR LOWER(e.medication) LIKE '%rosiglitazone%'
        OR LOWER(e.medication) LIKE '%sitagliptin%'
        OR LOWER(e.medication) LIKE '%saxagliptin%'
        OR LOWER(e.medication) LIKE '%linagliptin%'
        OR LOWER(e.medication) LIKE '%canagliflozin%'
        OR LOWER(e.medication) LIKE '%dapagliflozin%'
        OR LOWER(e.medication) LIKE '%empagliflozin%'
        THEN 'Oral Agent'
      ELSE NULL
    END AS drug_category
  FROM cohort AS c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON c.hadm_id = e.hadm_id
  -- Ensure the medication administration happened during the hospital stay
  WHERE e.charttime BETWEEN c.admittime AND c.dischtime
),
patient_drug_windows AS (
  -- Step 3: For each patient and drug category, flag if administered in the time windows
  SELECT
    hadm_id,
    drug_category,
    MAX(CASE WHEN charttime <= TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS given_first_24h,
    MAX(CASE WHEN charttime >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS given_last_48h
  FROM med_admin
  WHERE
    drug_category IS NOT NULL
  GROUP BY
    hadm_id,
    drug_category
)
-- Step 4: Aggregate the window flags to compute final prevalence and transition counts
SELECT
  pdw.drug_category,
  (SELECT COUNT(DISTINCT hadm_id) FROM cohort) AS total_patients_in_cohort,

  -- Prevalence calculation
  SAFE_DIVIDE(SUM(pdw.given_first_24h) * 100, (SELECT COUNT(DISTINCT hadm_id) FROM cohort)) AS prevalence_first_24h_pct,
  SAFE_DIVIDE(SUM(pdw.given_last_48h) * 100, (SELECT COUNT(DISTINCT hadm_id) FROM cohort)) AS prevalence_last_48h_pct,

  -- Transition counts
  SUM(CASE WHEN pdw.given_first_24h = 1 AND pdw.given_last_48h = 1 THEN 1 ELSE 0 END) AS continued_count,
  SUM(CASE WHEN pdw.given_first_24h = 0 AND pdw.given_last_48h = 1 THEN 1 ELSE 0 END) AS initiated_count,
  SUM(CASE WHEN pdw.given_first_24h = 1 AND pdw.given_last_48h = 0 THEN 1 ELSE 0 END) AS discontinued_count
FROM patient_drug_windows AS pdw
GROUP BY
  pdw.drug_category
ORDER BY
  pdw.drug_category;