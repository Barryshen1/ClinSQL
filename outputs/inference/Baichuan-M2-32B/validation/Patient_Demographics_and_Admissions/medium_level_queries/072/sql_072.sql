WITH first_service AS (
  SELECT
    subject_id,
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
admissions_with_service AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    fs.curr_service
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN first_service fs
    ON a.subject_id = fs.subject_id
    AND a.hadm_id = fs.hadm_id
    AND fs.rn = 1
  WHERE
    a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND p.gender = 'M'
    AND fs.curr_service = 'Medicine'
),
filtered_admissions AS (
  SELECT
    *,
    (a.anchor_age + EXTRACT(YEAR FROM a.admittime) - a.anchor_year) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM admissions_with_service a
  WHERE (a.anchor_age + EXTRACT(YEAR FROM a.admittime) - a.anchor_year) BETWEEN 74 AND 84
),
outcomes AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location LIKE '%Hospice%' THEN 'hospice'
      WHEN discharge_location LIKE '%Home%' THEN 'home'
    END AS outcome
  FROM filtered_admissions
)
SELECT
  outcome,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  AVG(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0 END) AS prop_los_le5
FROM outcomes
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY outcome;