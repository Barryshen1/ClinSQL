WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    -- Discharge outcome categories
    CASE
      WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    LOWER(p.gender) IN ('m', 'male')
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- Age at admission between 74 and 84 (inclusive)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
    -- Exclude ICU stays for this admission (non-ICU Medicine inpatients)
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = a.hadm_id
    )
    -- Confirm Medicine service involvement (ward transfers)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
      WHERE t.hadm_id = a.hadm_id
        AND t.subject_id = a.subject_id
        AND LOWER(t.careunit) LIKE '%medicine%'
    )
    -- Must be discharged (has a discharge time)
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  AVG(los_days) AS mean_los,
  MEDIAN(los_days) AS median_los,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days <= 5.0 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS prop_los_le5
FROM base
WHERE discharge_group IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;