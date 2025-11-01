WITH patient_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    i.stay_id,
    i.los AS icu_los,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),

discharge_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN discharge_location LIKE '%Home%' THEN 'Home'
      WHEN discharge_location LIKE '%Facility%' OR
           discharge_location LIKE '%Nursing%' OR
           discharge_location LIKE '%Rehab%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category,
    hospital_los,
    icu_los
  FROM
    patient_data
)

SELECT
  discharge_category,
  COUNT(*) AS patient_count,
  ROUND(AVG(hospital_los), 2) AS mean_hospital_los_days,
  ROUND(APPROX_QUANTILES(hospital_los, 4)[OFFSET(1)], 2) AS median_hospital_los_days,
  ROUND(APPROX_QUANTILES(hospital_los, 4)[OFFSET(2)], 2) AS p75_hospital_los_days,
  ROUND(APPROX_QUANTILES(hospital_los, 10)[OFFSET(8)], 2) AS p90_hospital_los_days,
  ROUND(AVG(icu_los), 2) AS mean_icu_los_days,
  ROUND(APPROX_QUANTILES(icu_los, 4)[OFFSET(1)], 2) AS median_icu_los_days,
  ROUND(APPROX_QUANTILES(icu_los, 4)[OFFSET(2)], 2) AS p75_icu_los_days,
  ROUND(APPROX_QUANTILES(icu_los, 10)[OFFSET(8)], 2) AS p90_icu_los_days
FROM
  discharge_categories
GROUP BY
  discharge_category
ORDER BY
  patient_count DESC;