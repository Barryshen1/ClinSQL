WITH cohort AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND UPPER(a.admission_location) LIKE '%TRANSFER%'
),
stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS total_n,
    COUNTIF(los <= 10) AS n_le10,
    APPROX_QUANTILES(los, 4) AS quartiles
  FROM
    cohort
  GROUP BY
    discharge_group
)
SELECT
  discharge_group,
  quartiles[OFFSET(1)] AS los_p25,
  quartiles[OFFSET(2)] AS los_median,
  quartiles[OFFSET(3)] AS los_p75,
  100.0 * n_le10 / total_n AS pct_le10
FROM
  stats
ORDER BY
  discharge_group;