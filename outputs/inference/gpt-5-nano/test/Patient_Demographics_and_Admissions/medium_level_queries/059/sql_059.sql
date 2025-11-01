WITH eligible AS (
  -- Population: female, aged 75-85 at admission, transferred from another hospital
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    a.deathtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.transfers` AS t
    ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
  WHERE UPPER(TRIM(p.gender)) = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.admission_type = 'TRANSFER'  -- transferred admissions
),

categorized AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_category,
    los_days
  FROM eligible
  WHERE CASE
          WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 'In-hospital death'
          WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
          WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
          ELSE 'Other'
        END IN ('Home','Hospice','In-hospital death')
),

stats AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_ge7,
    SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge7
  FROM categorized
  GROUP BY discharge_category
),

-- Determine the 7th percentile of LOS days across all eligible admissions
approx_quant AS (
  SELECT APPROX_QUANTILES(los_days, 100) AS quant_arr
  FROM eligible
),

seven_pctl AS (
  SELECT quant_arr[OFFSET(6)] AS seven_pctl
  FROM approx_quant
)

SELECT
  s.discharge_category,
  s.total_patients,
  s.n_ge7,
  s.prop_ge7,
  seven_pctl.seven_pctl AS seven_day_percentile
FROM stats AS s
CROSS JOIN seven_pctl
ORDER BY s.discharge_category;