WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND i.stay_id IS NULL  -- No ICU stay
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
stratified_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Discharged to Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged Home'
      ELSE NULL
    END AS discharge_group
  FROM patient_ages
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS std_los_days
FROM
  stratified_groups
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;