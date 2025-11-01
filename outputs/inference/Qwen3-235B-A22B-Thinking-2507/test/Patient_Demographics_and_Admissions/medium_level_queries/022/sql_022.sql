WITH base AS (
  SELECT
    adm.hadm_id,
    adm.discharge_location,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND adm.dischtime IS NOT NULL
    AND (
      pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
    ) BETWEEN 81 AND 91
),
categorized AS (
  SELECT
    hadm_id,
    CASE
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'ASSISTED LIVING') THEN 'home'
      WHEN discharge_location IN ('HOSPICE - HOME', 'HOSPICE - MEDICAL FACILITY') THEN 'hospice'
      WHEN discharge_location = 'DEAD/EXPIRED' THEN 'death'
      ELSE NULL
    END AS discharge_category,
    los_days
  FROM base
  WHERE discharge_location IN (
    'HOME', 'HOME HEALTH CARE', 'ASSISTED LIVING',
    'HOSPICE - HOME', 'HOSPICE - MEDICAL FACILITY',
    'DEAD/EXPIRED'
  )
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90,
  AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0 END) * 100 AS percent_los_le_10
FROM categorized
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY 
  CASE discharge_category
    WHEN 'home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'death' THEN 3
  END;