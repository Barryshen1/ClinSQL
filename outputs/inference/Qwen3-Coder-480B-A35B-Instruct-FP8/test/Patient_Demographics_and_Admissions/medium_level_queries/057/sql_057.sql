WITH cohort AS (
  SELECT
    i.los,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
)

SELECT
  discharge_outcome,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  AVG(IF(los <= 7, 1.0, 0.0)) * 100 AS pct_less_than_7_days
FROM
  cohort
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;