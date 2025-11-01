WITH cohort_admissions AS (
  -- Female patients aged 68-78 with T2DM AND heart failure
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    -- Restrict age and gender
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Must have both diagnoses
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%type 2 diabetes mellitus%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
med_exposures AS (
  -- Determine exposures in the two windows per admission and drug class
  SELECT
    ca.hadm_id,
    CASE
      WHEN LOWER(r.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(r.drug) LIKE '%glipizide%'
        OR LOWER(r.drug) LIKE '%glyburide%'
        OR LOWER(r.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(r.drug) LIKE '%gliptin%' THEN 'DPP4 inhibitors'
      WHEN LOWER(r.drug) LIKE '%flozin%' THEN 'SGLT2 inhibitors'
      ELSE NULL
    END AS drug_class,
    MAX(
      CASE
        WHEN r.starttime >= ca.admittime
         AND r.starttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
        THEN 1 ELSE 0
      END
    ) AS exposed_48h,
    MAX(
      CASE
        WHEN r.starttime >= TIMESTAMP_SUB(ca.dischtime, INTERVAL 12 HOUR)
         AND r.starttime < ca.dischtime
        THEN 1 ELSE 0
      END
    ) AS exposed_last12h
  FROM
    cohort_admissions ca
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` r
      ON ca.hadm_id = r.hadm_id
  WHERE
    -- Only consider the four classes
    (
      LOWER(r.drug) LIKE '%metformin%'
      OR LOWER(r.drug) LIKE '%glipizide%'
      OR LOWER(r.drug) LIKE '%glyburide%'
      OR LOWER(r.drug) LIKE '%glimepiride%'
      OR LOWER(r.drug) LIKE '%gliptin%'
      OR LOWER(r.drug) LIKE '%flozin%'
    )
    AND r.starttime BETWEEN ca.admittime - INTERVAL 1 DAY
                         AND ca.dischtime + INTERVAL 1 DAY
      -- broaden a bit to catch boundary cases
  GROUP BY
    ca.hadm_id,
    drug_class
),
class_aggregates AS (
  -- Compute counts and percentages per drug class
  SELECT
    drug_class,
    COUNTIF(exposed_48h = 1) AS cnt_48h,
    COUNTIF(exposed_last12h = 1) AS cnt_last12h,
    COUNT(*) AS n_adm
  FROM
    med_exposures
  GROUP BY
    drug_class
),
total_adm AS (
  -- Total number of admissions in the cohort
  SELECT
    COUNT(DISTINCT hadm_id) AS total_n
  FROM
    cohort_admissions
)
SELECT
  ca.drug_class,
  ROUND(100.0 * ca.cnt_48h   / t.total_n, 1) AS pct_first_48h,
  ROUND(100.0 * ca.cnt_last12h / t.total_n, 1) AS pct_last_12h,
  ROUND(
    100.0 * ca.cnt_last12h / t.total_n
    - 100.0 * ca.cnt_48h   / t.total_n
  , 1) AS net_pct_point_change
FROM
  class_aggregates ca
  CROSS JOIN total_adm t
ORDER BY
  ca.drug_class;