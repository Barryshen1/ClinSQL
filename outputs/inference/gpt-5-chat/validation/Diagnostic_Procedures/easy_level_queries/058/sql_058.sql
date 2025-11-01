WITH mech_support_counts AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_mech_support_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(dp.long_title) LIKE '%ventricular assist%'
    OR LOWER(dp.long_title) LIKE '%mechanical circulatory support%'
    OR LOWER(dp.long_title) LIKE '%ecmo%'
    OR LOWER(dp.long_title) LIKE '%circulatory assist%'
  GROUP BY
    p.subject_id, pr.hadm_id
)
SELECT
  q_vals[OFFSET(2)] - q_vals[OFFSET(0)] AS iqr_mech_support_per_hosp
FROM (
  SELECT
    APPROX_QUANTILES(distinct_mech_support_procs, 4) AS q_vals
  FROM
    mech_support_counts
);