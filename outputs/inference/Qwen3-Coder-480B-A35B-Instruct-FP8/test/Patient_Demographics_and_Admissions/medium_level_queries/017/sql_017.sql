WITH cohort AS (
  SELECT
    i.los,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE 'Facility'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.discharge_location IS NOT NULL
)

SELECT
  discharge_group,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
FROM
  cohort
GROUP BY
  discharge_group
ORDER BY
  discharge_group;