WITH temp_first24 AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND di.label LIKE '%Temperature%Celsius%'
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 20
    AND ce.valuenum < 45
  GROUP BY
    ce.stay_id
),
classified AS (
  SELECT
    stay_id,
    mean_temp,
    CASE
      WHEN mean_temp < 36.0 THEN '<36.0'
      WHEN mean_temp >= 36.0 AND mean_temp <= 37.9 THEN '36.0–37.9'
      WHEN mean_temp >= 38.0 THEN '≥38.0'
    END AS temp_class
  FROM
    temp_first24
),
stay_mortality AS (
  SELECT
    ie.stay_id,
    adm.hospital_expire_flag AS died
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
)
SELECT
  c.temp_class,
  COUNT(*) AS n_stays,
  AVG(c.mean_temp) AS mean_temp,
  APPROX_QUANTILES(c.mean_temp, 2)[OFFSET(1)] AS median_temp,
  APPROX_QUANTILES(c.mean_temp, 4)[OFFSET(1)] AS q1_temp,
  APPROX_QUANTILES(c.mean_temp, 4)[OFFSET(3)] AS q3_temp,
  ROUND(AVG(s.died) * 100, 2) AS mortality_rate_percent
FROM
  classified c
JOIN
  stay_mortality s
  ON c.stay_id = s.stay_id
GROUP BY
  c.temp_class
ORDER BY
  CASE c.temp_class
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
  END;