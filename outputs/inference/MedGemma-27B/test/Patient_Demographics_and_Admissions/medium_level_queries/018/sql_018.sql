WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.dischtime,
    a.deathtime,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53 AND a.admission_type = 'TRANSFER'
), DischargeInfo AS (
  SELECT
    subject_id,
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SNF', 'HOSPICE', 'REHAB', 'NURSING HOME') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    PatientInfo
), LOSCalculation AS (
  SELECT
    pi.subject_id,
    CASE
      WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      ELSE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)
    END AS los
  FROM
    PatientInfo AS pi
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pi.subject_id = a.subject_id
)
SELECT
  di.discharge_category,
  PERCENTILE_CONT(0.5, los) AS median_los,
  PERCENTILE_CONT(0.25, los) AS iqr_25,
  PERCENTILE_CONT(0.75, los) AS iqr_75,
  (COUNT(CASE WHEN los <= 10 THEN 1 ELSE NULL END) / COUNT(los)) * 100 AS percent_le_10_days
FROM
  LOSCalculation AS l
INNER JOIN
  DischargeInfo AS di
  ON l.subject_id = di.subject_id
GROUP BY
  di.discharge_category
ORDER BY
  di.discharge_category;