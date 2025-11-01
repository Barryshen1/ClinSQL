WITH cohort_los AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Calculate Length of Stay in fractional days for precision
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- Filter for male patients
    pat.gender = 'M'
    -- Filter for patients aged 67-77 at the time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 67 AND 77
    -- Filter for admissions originating from the Emergency Room
    AND adm.admission_location = 'EMERGENCY ROOM'
    -- Ensure dischtime is available to calculate LOS
    AND adm.dischtime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1
    THEN 'Died'
    ELSE 'Alive'
  END AS discharge_status,
  COUNT(hadm_id) AS number_of_patients,
  -- Calculate proportion with LOS >= 7 days
  AVG(
    CASE
      WHEN los_days >= 7
      THEN 1.0
      ELSE 0.0
    END
  ) AS proportion_los_ge_7_days,
  -- Calculate proportion with LOS >= 14 days
  AVG(
    CASE
      WHEN los_days >= 14
      THEN 1.0
      ELSE 0.0
    END
  ) AS proportion_los_ge_14_days,
  -- Calculate percentile rank for a 10-day LOS, interpreted as the
  -- proportion of patients with LOS <= 10 days (cumulative distribution)
  AVG(
    CASE
      WHEN los_days <= 10
      THEN 1.0
      ELSE 0.0
    END
  ) AS percentile_rank_los_10_days
FROM
  cohort_los
GROUP BY
  discharge_status
ORDER BY
  discharge_status DESC;