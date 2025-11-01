WITH cohort AS (
  SELECT
    ie.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN a.discharge_location = 'HOME' THEN 'home'
    END AS outcome
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    ie.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    ie.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      p.anchor_age + EXTRACT(YEAR FROM ie.intime) - p.anchor_year
    ) BETWEEN 40 AND 50
    AND (
      a.hospital_expire_flag = 1
      OR a.discharge_location IN ('HOME', 'HOSPICE')
    )
)
SELECT
  outcome,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  SAFE_DIVIDE(COUNTIF(los <= 7), COUNT(*)) * 100 AS pct_le_7_days
FROM
  cohort
GROUP BY
  outcome
ORDER BY
  outcome;