WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    a.hospital_expire_flag,
    d.long_title AS diagnosis,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_stay_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code = 'A41.9' -- Sepsis without organ failure
    AND d.icd_version = '9'
),
UltrasoundCounts AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.icu_stay_flag,
    COUNT(DISTINCT pe.itemid) AS ultrasound_count
  FROM
    PatientCohort AS pc
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON pc.subject_id = pe.subject_id
    AND pc.hadm_id = pe.hadm_id
  WHERE
    pe.itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        label LIKE '%ultrasound%'
    )
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.icu_stay_flag
),
LOSCalculation AS (
  SELECT
    uc.subject_id,
    uc.hadm_id,
    uc.icu_stay_flag,
    uc.ultrasound_count,
    -- Calculate LOS in days
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS los
  FROM
    UltrasoundCounts AS uc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON uc.hadm_id = a.hadm_id
  WHERE
    a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT
  icu_stay_flag,
  CASE
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Other'
  END AS los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM
  LOSCalculation
WHERE
  los BETWEEN 1 AND 8
GROUP BY
  icu_stay_flag,
  los_group
ORDER BY
  icu_stay_flag,
  los_group;