WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
  ON
    p.subject_id = i.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

vitals AS (
  SELECT
    c.stay_id,
    c.charttime,
    MAX(CASE WHEN di.label = 'Temperature Celsius' AND c.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever,
    MAX(CASE WHEN di.label = 'SpO2' AND c.valuenum < 90 THEN 1 ELSE 0 END) AS hypoxemia,
    MAX(CASE WHEN di.label = 'Respiratory Rate' AND c.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents c
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
  ON
    c.itemid = di.itemid
  WHERE
    di.label IN ('Temperature Celsius', 'SpO2', 'Respiratory Rate')
    AND c.valuenum IS NOT NULL
  GROUP BY
    c.stay_id, c.charttime
),

instability_per_hour AS (
  SELECT
    v.stay_id,
    DATETIME_TRUNC(v.charttime, HOUR) AS chart_hour,
    MAX(v.fever) AS fever,
    MAX(v.hypoxemia) AS hypoxemia,
    MAX(v.tachypnea) AS tachypnea
  FROM
    vitals v
  JOIN
    cohort c
  ON
    v.stay_id = c.stay_id
  WHERE
    v.charttime >= c.intime
    AND v.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    v.stay_id, chart_hour
),

instability_per_stay AS (
  SELECT
    stay_id,
    COUNT(*) AS instability_hours,
    SUM(fever) AS fever_hours,
    SUM(hypoxemia) AS hypoxemia_hours,
    SUM(tachypnea) AS tachypnea_hours
  FROM
    instability_per_hour
  GROUP BY
    stay_id
),

percentile_90 AS (
  SELECT
    APPROX_QUANTILES(instability_hours, 10)[OFFSET(9)] AS p90
  FROM
    instability_per_stay
),

top_decile AS (
  SELECT
    ips.*
  FROM
    instability_per_stay ips
  CROSS JOIN
    percentile_90 p90
  WHERE
    ips.instability_hours >= p90.p90
),

top_decile_summary AS (
  SELECT
    COUNT(*) AS n,
    AVG(c.los) AS mean_icu_los,
    AVG(c.hospital_expire_flag) AS mortality_rate,
    AVG(ips.fever_hours) AS mean_fever_hours,
    AVG(ips.hypoxemia_hours) AS mean_hypoxemia_hours,
    AVG(ips.tachypnea_hours) AS mean_tachypnea_hours
  FROM
    top_decile ips
  JOIN
    cohort c
  ON
    ips.stay_id = c.stay_id
)

SELECT
  (SELECT p90 FROM percentile_90) AS p90_instability_hours,
  n,
  mean_icu_los,
  mortality_rate * 100 AS mortality_percent,
  mean_fever_hours,
  mean_hypoxemia_hours,
  mean_tachypnea_hours
FROM
  top_decile_summary;