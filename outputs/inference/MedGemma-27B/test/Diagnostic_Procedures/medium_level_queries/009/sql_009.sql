WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 44 AND 54
    AND gender = 'F'
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.los,
    CASE
      WHEN a.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN a.los BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'Other'
    END AS los_group,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE
          icu.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_use
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND a.los IS NOT NULL
    AND a.los > 0
), ImagingEvents AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS imaging_count
  FROM
    AdmissionInfo AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON a.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd LIKE '7%' -- Assuming HCPCS codes starting with 7 are diagnostic imaging
  GROUP BY
    a.hadm_id
)
SELECT
  los_group,
  icu_use,
  PERCENTILE_CONT(imaging_count, 0.25) AS p25,
  PERCENTILE_CONT(imaging_count, 0.50) AS p50,
  PERCENTILE_CONT(imaging_count, 0.75) AS p75
FROM
  AdmissionInfo AS a
LEFT JOIN
  ImagingEvents AS ie
  ON a.hadm_id = ie.hadm_id
WHERE
  los_group IN ('1-4 days', '5-7 days')
GROUP BY
  los_group,
  icu_use
ORDER BY
  los_group,
  icu_use;