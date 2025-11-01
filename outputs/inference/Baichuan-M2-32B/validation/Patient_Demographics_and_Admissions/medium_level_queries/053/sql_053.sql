WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    -- Approximate birth date: Jan 1 of anchor_year minus anchor_age years
    DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'Emergency'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
filtered AS (
  SELECT
    *,
    -- Age at admission (years)
    TIMESTAMP_DIFF(TIMESTAMP(admittime), TIMESTAMP(birth_date), YEAR) AS age_at_admission,
    -- Length of stay (days)
    DATEDIFF(dischtime, admittime) AS los
  FROM patient_admissions
  WHERE
    TIMESTAMP_DIFF(TIMESTAMP(admittime), TIMESTAMP(birth_date), YEAR) BETWEEN 77 AND 87
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location LIKE '%Home%' THEN 'home'
      WHEN discharge_location LIKE '%Hospice%' THEN 'hospice'
      ELSE 'other'
    END AS discharge_group
  FROM filtered
)
SELECT
  discharge_group,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75
FROM discharge_groups
WHERE discharge_group IN ('home', 'hospice', 'in-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;