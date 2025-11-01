WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 44 AND 54 AND a.admission_type = 'ELECTIVE'
),
LOSCalculation AS (
  SELECT
    subject_id,
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital mortality'
      ELSE 'Discharged alive'
    END AS mortality_status,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM
    PatientInfo
)
SELECT
  mortality_status,
  COUNT(subject_id) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 4) AS percentiles -- Corrected line
FROM
  LOSCalculation
GROUP BY
  mortality_status
ORDER BY
  mortality_status;