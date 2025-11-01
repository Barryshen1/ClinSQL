WITH female_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    -- Calculate length of stay in days
    CASE
      WHEN a.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      ELSE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)
    END AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
    -- Exclude patients with ICU stays
    AND a.subject_id NOT IN (
      SELECT DISTINCT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.transfers`
      WHERE careunit LIKE '%ICU%'
    )
),

discharge_outcomes AS (
  SELECT
    CASE
      WHEN discharge_location LIKE '%Home%' THEN 'Discharged Home'
      WHEN discharge_location LIKE '%Hospice%' THEN 'Discharged to Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      ELSE 'Other'
    END AS discharge_outcome,
    length_of_stay_days
  FROM
    female_inpatients
)

SELECT
  discharge_outcome,
  COUNT(*) AS patient_count,
  AVG(length_of_stay_days) AS mean_los_days,
  STDDEV(length_of_stay_days) AS sd_los_days
FROM
  discharge_outcomes
WHERE
  discharge_outcome IN ('Discharged Home', 'Discharged to Hospice', 'In-Hospital Mortality')
GROUP BY
  discharge_outcome
ORDER BY
  patient_count DESC;