WITH cardiac_procedures AS (
  SELECT
    icd_code,
    icd_version
  FROM
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures
  WHERE
    LOWER(long_title) LIKE '%cardiac%'
    OR LOWER(long_title) LIKE '%heart%'
    OR LOWER(long_title) LIKE '%coronary%'
    OR LOWER(long_title) LIKE '%bypass%'
    OR LOWER(long_title) LIKE '%angioplasty%'
    OR LOWER(long_title) LIKE '%valve%'
    OR LOWER(long_title) LIKE '%myocardial%'
    OR LOWER(long_title) LIKE '%pacemaker%'
    OR LOWER(long_title) LIKE '%defibrillator%'
    OR LOWER(long_title) LIKE '%catheter%'
    OR LOWER(long_title) LIKE '%stenosis%'
    OR LOWER(long_title) LIKE '%ischemia%'
    OR LOWER(long_title) LIKE '%infarction%'
),
eligible_admissions AS (
  SELECT
    p.hadm_id,
    p.icd_code
  FROM
    physionet-data.mimiciv_3_1_hosp.patients pat
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
    ON pat.subject_id = p.subject_id
  INNER JOIN
    cardiac_procedures cp
    ON p.icd_code = cp.icd_code AND p.icd_version = cp.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND p.hadm_id IS NOT NULL
),
procedures_per_admission AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_cardiac_procedures
  FROM
    eligible_admissions
  GROUP BY
    hadm_id
)
SELECT
  APPROX_QUANTILES(num_cardiac_procedures, 100)[OFFSET(25)] AS twenty_fifth_percentile
FROM
  procedures_per_admission;