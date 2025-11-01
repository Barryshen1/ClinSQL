WITH male_57_67 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
echo_procedures AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%echocardi%'
),
per_patient_counts AS (
  SELECT
    mp.subject_id,
    COUNT(DISTINCT CONCAT(ep.hadm_id, '_', ep.icd_code)) AS echo_count
  FROM
    male_57_67 mp
  LEFT JOIN
    echo_procedures ep
    ON mp.subject_id = ep.subject_id
  GROUP BY
    mp.subject_id
)
SELECT
  -- Approximate 75th percentile of echocardiography counts
  APPROX_QUANTILES(echo_count, 100)[OFFSET(75)] AS p75_echo_procedures
FROM
  per_patient_counts;