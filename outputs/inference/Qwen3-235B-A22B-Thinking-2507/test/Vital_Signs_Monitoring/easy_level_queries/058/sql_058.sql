WITH eligible_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 74 AND 84
),
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients e
    ON i.subject_id = e.subject_id AND i.hadm_id = e.hadm_id
),
stay_min_temps AS (
  SELECT
    s.stay_id,
    MIN((c.valuenum * 9/5) + 32) AS min_temp_f
  FROM icu_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE c.itemid = 223762  -- Standard core temperature itemid (Celsius)
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id
)
SELECT
  APPROX_QUANTILES(min_temp_f, 10000)[OFFSET(5000)] AS median_min_temp_f
FROM stay_min_temps;