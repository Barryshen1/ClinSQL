WITH elig_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
    )
),
proc_counts AS (
  SELECT
    ea.hadm_id,
    ea.los,
    COUNT(*) AS diag_proc_count
  FROM
    elig_adm ea
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pr.subject_id = ea.subject_id
    AND pr.hadm_id = ea.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%diagnostic%'
  GROUP BY
    ea.hadm_id,
    ea.los
),
bucketed AS (
  SELECT
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4'
      ELSE '5-8'
    END AS los_bucket,
    diag_proc_count
  FROM
    proc_counts
)
SELECT
  los_bucket,
  -- APPROX_QUANTILES returns an array of length 5: [min, Q1, Q2, Q3, max]
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM (
  SELECT
    los_bucket,
    APPROX_QUANTILES(diag_proc_count, 4) AS quantiles
  FROM
    bucketed
  GROUP BY
    los_bucket
)
ORDER BY
  los_bucket;