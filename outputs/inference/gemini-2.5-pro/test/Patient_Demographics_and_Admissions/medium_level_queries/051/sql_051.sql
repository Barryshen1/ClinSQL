WITH cohort AS (
  SELECT
    adm.hadm_id,
    adm.discharge_location,
    -- Calculate Length of Stay (LOS) in days, including fractional parts for accuracy.
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / (24.0 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- 1. Filter for male patients
    pat.gender = 'M'
    -- 2. Filter for admissions from the Emergency Room
    AND adm.admission_location = 'EMERGENCY ROOM'
    -- 3. Calculate and filter by age at admission (68-78 years old)
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 68 AND 78
)
SELECT
  -- Group by the patient's discharge location
  cohort.discharge_location,
  -- Count the number of patients in each group
  COUNT(cohort.hadm_id) AS number_of_patients,
  -- Calculate and format mean ± standard deviation for LOS
  CONCAT(
    CAST(ROUND(AVG(cohort.los_days), 2) AS STRING),
    ' ± ',
    CAST(ROUND(STDDEV(cohort.los_days), 2) AS STRING)
  ) AS mean_sd_los_days,
  -- Calculate the percentage of stays with LOS <= 7 days
  ROUND(AVG(CASE WHEN cohort.los_days <= 7 THEN 1 ELSE 0 END) * 100, 2) AS percent_los_le_7_days
FROM
  cohort
WHERE
  -- Exclude admissions where LOS cannot be calculated (e.g., missing discharge time)
  cohort.los_days IS NOT NULL
GROUP BY
  cohort.discharge_location
ORDER BY
  number_of_patients DESC;