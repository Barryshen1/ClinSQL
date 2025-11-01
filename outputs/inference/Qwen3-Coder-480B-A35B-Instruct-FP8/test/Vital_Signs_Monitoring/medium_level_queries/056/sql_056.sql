WITH temp_measurements AS (
  SELECT
    p.subject_id,
    a.hospital_expire_flag,
    ce.valuenum AS temp_value,
    CASE
      WHEN ce.valuenum < 36 THEN '<36'
      WHEN ce.valuenum BETWEEN 36 AND 37.9 THEN '36-37.9'
      ELSE '>=38'
    END AS temp_category
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND di.label LIKE '%Temperature%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 20
    AND ce.valuenum < 50
)

SELECT
  temp_category,
  COUNT(*) AS measurement_count,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(temp_value) AS mean_temp,
  APPROX_QUANTILES(temp_value, 2)[OFFSET(1)] AS median_temp,
  APPROX_QUANTILES(temp_value, 4)[OFFSET(1)] AS q1_temp,
  APPROX_QUANTILES(temp_value, 4)[OFFSET(3)] AS q3_temp,
  (COUNTIF(hospital_expire_flag = 1) * 100.0 / COUNT(*)) AS mortality_rate
FROM
  temp_measurements
GROUP BY
  temp_category
ORDER BY
  CASE temp_category
    WHEN '<36' THEN 1
    WHEN '36-37.9' THEN 2
    WHEN '>=38' THEN 3
  END;