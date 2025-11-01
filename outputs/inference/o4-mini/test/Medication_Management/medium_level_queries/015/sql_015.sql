WITH
-- 1. Define ICU cohort with demographics
icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id
   AND icu.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    -- Require at least one diabetes diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.subject_id = icu.subject_id
        AND d.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- Require at least one acute heart failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.subject_id = icu.subject_id
        AND d.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute% heart failure%'
    )
),
-- 2. Classify antidiabetic prescriptions and flag windows
presc_flags AS (
  SELECT
    c.stay_id,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%gli%'  /* e.g. glimepiride, glyburide */ THEN 'Sulfonylurea'
      WHEN LOWER(pr.drug) LIKE '%gliptin%' THEN 'DPP-4'
      WHEN LOWER(pr.drug) LIKE '%gliflozin%' THEN 'SGLT2'
      WHEN LOWER(pr.drug) LIKE '%tide%'     /* e.g. liraglutide */ THEN 'GLP-1'
      WHEN LOWER(pr.drug) LIKE '%glitazone%' OR LOWER(pr.drug) LIKE '%pioglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class,
    -- Flag if given in first 24h
    MAX(
      CASE
        WHEN pr.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
        THEN 1 ELSE 0
      END
    ) AS first24_flag,
    -- Flag if given in final 12h
    MAX(
      CASE
        WHEN pr.stoptime BETWEEN TIMESTAMP_SUB(c.outtime, INTERVAL 12 HOUR) AND c.outtime
        THEN 1 ELSE 0
      END
    ) AS final12_flag
  FROM icu_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
   AND c.hadm_id    = pr.hadm_id
  WHERE pr.drug IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%insulin%'
      OR LOWER(pr.drug) LIKE '%metformin%'
      OR LOWER(pr.drug) LIKE '%gli%'
      OR LOWER(pr.drug) LIKE '%gliptin%'
      OR LOWER(pr.drug) LIKE '%gliflozin%'
      OR LOWER(pr.drug) LIKE '%tide%'
      OR LOWER(pr.drug) LIKE '%glitazone%'
      OR LOWER(pr.drug) LIKE '%pioglitazone%'
    )
  GROUP BY c.stay_id, drug_class
  HAVING drug_class IS NOT NULL
),
-- 3. Count total stays in cohort
total_stays AS (
  SELECT COUNT(DISTINCT stay_id) AS n_cohort
  FROM icu_cohort
),
-- 4. Aggregate prevalence by class
agg AS (
  SELECT
    pf.drug_class,
    SUM(pf.first24_flag) AS n_first24,
    SUM(pf.final12_flag) AS n_final12
  FROM presc_flags pf
  GROUP BY pf.drug_class
)
-- 5. Compute percentages and net change
SELECT
  a.drug_class,
  ROUND(100.0 * a.n_first24  / t.n_cohort, 1) AS first24_pct,
  ROUND(100.0 * a.n_final12  / t.n_cohort, 1) AS final12_pct,
  ROUND(
    100.0 * a.n_final12 / t.n_cohort
    - 100.0 * a.n_first24 / t.n_cohort
  , 1) AS net_change_pct_points
FROM agg a
CROSS JOIN total_stays t
ORDER BY a.drug_class;