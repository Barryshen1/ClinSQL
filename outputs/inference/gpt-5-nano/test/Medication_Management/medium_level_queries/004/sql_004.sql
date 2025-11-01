WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'Male'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_t2dm
      WHERE d_t2dm.subject_id = a.subject_id
        AND d_t2dm.hadm_id = a.hadm_id
        AND (
          (d_t2dm.icd_version = 9 AND d_t2dm.icd_code LIKE '250%')
          OR
          (d_t2dm.icd_version = 10 AND d_t2dm.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_hf
      WHERE d_hf.subject_id = a.subject_id
        AND d_hf.hadm_id = a.hadm_id
        AND (
          (d_hf.icd_version = 9 AND d_hf.icd_code LIKE '428%')
          OR
          (d_hf.icd_version = 10 AND d_hf.icd_code LIKE 'I50%')
        )
    )
),
tot AS (
  SELECT COUNT(*) AS total_cohort
  FROM cohort
),
within72 AS (
  SELECT
    COUNT(DISTINCT c.hadm_id) AS n72
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
  WHERE LOWER(pr.drug) IN (
        'liraglutide','exenatide','dulaglutide','lixisenatide','semaglutide','albiglutide'
        )
    AND pr.starttime >= c.admittime
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),
last48 AS (
  SELECT
    COUNT(DISTINCT c.hadm_id) AS n48
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
  WHERE LOWER(pr.drug) IN (
        'liraglutide','exenatide','dulaglutide','lixisenatide','semaglutide','albiglutide'
        )
    AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
    AND pr.starttime <= c.dischtime
)

SELECT
  -- Guard divisions to avoid division by zero; default to 0 when cohort is empty
  COALESCE(ROUND((n72 * 100.0) / NULLIF(total_cohort, 0), 2), 0) AS pct_started_within_72h,
  COALESCE(ROUND((n48 * 100.0) / NULLIF(total_cohort, 0), 2), 0) AS pct_on_last_48h,
  COALESCE(ROUND(((n72 - n48) * 100.0) / NULLIF(total_cohort, 0), 2), 0) AS net_change_pp
FROM
  tot
  CROSS JOIN within72
  CROSS JOIN last48;