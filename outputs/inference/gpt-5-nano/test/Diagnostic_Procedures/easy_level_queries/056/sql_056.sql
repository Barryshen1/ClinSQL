WITH cohort AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT ci.icd_code) AS mcs_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS ci
    ON p.subject_id = ci.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON ci.icd_code = d.icd_code
    AND ci.icd_version = d.icd_version
  WHERE
    LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      LOWER(d.long_title) LIKE '%ecmo%'
      OR LOWER(d.long_title) LIKE '%ventricular assist device%'
      OR LOWER(d.long_title) LIKE '%intra-aortic balloon pump%'
    )
  GROUP BY
    p.subject_id
)

SELECT
  -- 25th percentile across patients
  quantiles[OFFSET(1)] AS percentile_25
FROM (
  SELECT
    APPROX_QUANTILES(mcs_count, 4) AS quantiles
  FROM
    cohort
  WHERE
    mcs_count IS NOT NULL
) AS t;