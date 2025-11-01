WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 71 AND 81
),

temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
),

first_48h_temperatures AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    temperature_items ti
  ON
    ce.itemid = ti.itemid
  JOIN
    cohort co
  ON
    ce.stay_id = co.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
  GROUP BY
    ce.stay_id
),

temp_category AS (
  SELECT
    stay_id,
    avg_temp,
    CASE
      WHEN avg_temp < 36.0 THEN '<36.0'
      WHEN avg_temp >= 36.0 AND avg_temp <= 37.9 THEN '36.0–37.9'
      WHEN avg_temp >= 38.0 THEN '≥38.0'
      ELSE 'Other'
    END AS temp_group
  FROM
    first_48h_temperatures
),

mi_flag AS (
  SELECT DISTINCT
    di.hadm_id,
    1 AS has_mi
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.long_title, r"(?i)myocardial infarction")
    OR REGEXP_CONTAINS(di.icd_code, r"^I21|^I22")
),

cohort_with_mi AS (
  SELECT
    tc.stay_id,
    tc.avg_temp,
    tc.temp_group,
    COALESCE(mi.has_mi, 0) AS has_mi
  FROM
    temp_category tc
  JOIN
    cohort co
  ON
    tc.stay_id = co.stay_id
  LEFT JOIN
    mi_flag mi
  ON
    co.hadm_id = mi.hadm_id
)

SELECT
  temp_group,
  COUNT(*) AS n_stays,
  AVG(avg_temp) AS mean_temp,
  APPROX_QUANTILES(avg_temp, 2)[OFFSET(1)] AS median_temp,
  APPROX_QUANTILES(avg_temp, 4)[OFFSET(1)] AS q1_temp,
  APPROX_QUANTILES(avg_temp, 4)[OFFSET(3)] AS q3_temp,
  ROUND(AVG(has_mi), 4) AS mi_rate
FROM
  cohort_with_mi
GROUP BY
  temp_group
ORDER BY
  CASE temp_group
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
  END;