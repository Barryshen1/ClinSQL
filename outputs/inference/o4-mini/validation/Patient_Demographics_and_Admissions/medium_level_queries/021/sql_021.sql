WITH surgical_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN 1
      ELSE 0
    END AS short_stay
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- keep only male patients age 67–77
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    -- require at least one ICD procedure to label as "surgical"
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      WHERE pr.hadm_id = a.hadm_id
    )
),

categorized AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In‐hospital mortality'
      WHEN hospital_expire_flag = 0
           AND discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Discharged home'
      WHEN hospital_expire_flag = 0
           AND discharge_location NOT IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Discharged to facility'
      ELSE 'Other'
    END AS outcome_category,
    los_days,
    short_stay
  FROM
    surgical_admissions
  WHERE
    -- exclude any ambiguous 'Other' category if desired
    TRUE
)

SELECT
  outcome_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SUM(short_stay) / COUNT(*), 1) AS pct_los_le_7d
FROM
  categorized
WHERE
  outcome_category IN (
    'In‐hospital mortality',
    'Discharged home',
    'Discharged to facility'
  )
GROUP BY
  outcome_category
ORDER BY
  -- to present in a logical order
  CASE outcome_category
    WHEN 'Discharged home' THEN 1
    WHEN 'Discharged to facility' THEN 2
    WHEN 'In‐hospital mortality' THEN 3
    ELSE 4
  END;