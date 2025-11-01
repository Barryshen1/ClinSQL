WITH first_admissions AS (
  -- First, identify the first hospital admission for each patient
  SELECT
    subject_id,
    hadm_id,
    admittime,
    hospital_expire_flag,
    -- Use ROW_NUMBER to rank admissions chronologically for each patient
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
patient_cohort AS (
  -- Next, build the cohort of male patients aged 73-83 at their first admission
  SELECT
    fa.hospital_expire_flag,
    -- Calculate age at the time of their first admission
    EXTRACT(YEAR FROM fa.admittime) - p.anchor_year + p.anchor_age AS age_at_first_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    first_admissions AS fa
    ON p.subject_id = fa.subject_id
  WHERE
    fa.rn = 1 -- Ensures we are only looking at the first admission
    AND p.gender = 'M' -- Filters for male patients
),
mortality_by_age AS (
  -- Then, calculate the in-hospital mortality rate for each specific age in the cohort
  SELECT
    age_at_first_admission,
    -- The average of the hospital_expire_flag (0 or 1) gives the mortality rate
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    patient_cohort
  WHERE
    age_at_first_admission BETWEEN 73 AND 83 -- Filters for the specified age range
  GROUP BY
    age_at_first_admission
)
-- Finally, calculate the 25th percentile of these age-specific mortality rates
SELECT
  APPROX_QUANTILES(mortality_rate, 100)[OFFSET(25)] AS p25_in_hospital_mortality
FROM
  mortality_by_age;