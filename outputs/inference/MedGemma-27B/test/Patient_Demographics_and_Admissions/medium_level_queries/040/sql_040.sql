WITH PatientCohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admission_type = 'SURG'
),
LOS AS (
  SELECT
    hadm_id,
    -- Calculate length of stay (LOS) in days
    -- If deathtime is not null, use deathtime instead of dischtime
    -- Use TIMESTAMP_DIFF to calculate the difference in days
    TIMESTAMP_DIFF(
      COALESCE(a.deathtime, a.dischtime),
      a.admittime,
      DAY
    ) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    hadm_id IN (
      SELECT
        hadm_id
      FROM
        PatientCohort
    )
),
DischargeLocation AS (
  SELECT
    hadm_id,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'Facility'
      WHEN a.discharge_location = 'HOSPITAL' THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    hadm_id IN (
      SELECT
        hadm_id
      FROM
        PatientCohort
    )
)
SELECT
  dl.discharge_category,
  COUNT(
    CASE
      WHEN l.los_days >= 7 THEN 1
    END
  ) AS count_los_ge_7,
  COUNT(
    CASE
      WHEN l.los_days >= 14 THEN 1
    END
  ) AS count_los_ge_14,
  COUNT(l.hadm_id) AS total_count,
  -- Calculate proportions
  COUNT(
    CASE
      WHEN l.los_days >= 7 THEN 1
    END
  ) * 100.0 / COUNT(l.hadm_id) AS proportion_los_ge_7,
  COUNT(
    CASE
      WHEN l.los_days >= 14 THEN 1
    END
  ) * 100.0 / COUNT(l.hadm_id) AS proportion_los_ge_14
FROM
  LOS AS l
INNER JOIN
  DischargeLocation AS dl
  ON l.hadm_id = dl.hadm_id
GROUP BY
  dl.discharge_category
ORDER BY
  dl.discharge_category;