WITH cohort AS (
  -- Define the target admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    -- has diabetes
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
          ON d.icd_code = diag.icd_code
          AND d.icd_version = diag.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(diag.long_title) LIKE '%diabetes%'
    )
    -- has heart failure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
          ON d.icd_code = diag.icd_code
          AND d.icd_version = diag.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(diag.long_title) LIKE '%heart failure%'
    )
),
total_cohort AS (
  -- Count total admissions in the cohort for denominator
  SELECT COUNT(DISTINCT hadm_id) AS n_cohort
  FROM cohort
),
exposures AS (
  -- Gather prescriptions in first 72h and last 24h
  SELECT
    c.hadm_id,
    p.drug_type,
    'first_72h' AS period
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime >= c.admittime
    AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)

  UNION ALL

  SELECT
    c.hadm_id,
    p.drug_type,
    'last_24h' AS period
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
    AND p.starttime <= c.dischtime
)

SELECT
  e.period,
  e.drug_type,
  ROUND(100.0 * COUNT(DISTINCT e.hadm_id) / tc.n_cohort, 1) AS pct_of_cohort
FROM exposures e
CROSS JOIN total_cohort tc
GROUP BY
  e.period,
  e.drug_type,
  tc.n_cohort
ORDER BY
  e.period,
  pct_of_cohort DESC;