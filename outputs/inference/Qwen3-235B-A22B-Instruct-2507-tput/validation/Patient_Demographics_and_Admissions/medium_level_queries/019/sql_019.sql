WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) >= 0 -- anchor_year is on or before admittime
),
filtered_admissions AS (
  SELECT *
  FROM patient_admissions
  WHERE
    age_at_admission BETWEEN 63 AND 73
    AND (
      admission_location LIKE '%HOSPITAL%'
      OR admission_location LIKE '%SKILLED NURSING%'
      OR admission_location LIKE '%ACUTE CARE%'
      OR admission_location LIKE '%LONG TERM CARE%'
    )
),
stratified_outcomes AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      ELSE NULL
    END AS outcome_group
  FROM filtered_admissions
  WHERE
    hospital_expire_flag = 1
    OR LOWER(discharge_location) LIKE '%hospice%'
    OR discharge_location = 'HOME'
)
SELECT
  outcome_group,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days
FROM
  stratified_outcomes
WHERE
  outcome_group IS NOT NULL
GROUP BY
  outcome_group
ORDER BY
  outcome_group;