WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- compute LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location LIKE 'EMERGENCY%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1
           OR UPPER(discharge_location) = 'DIED'
        THEN 'Death'
      WHEN UPPER(discharge_location) LIKE 'HOME%'
        THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%SKILLED%'
        OR UPPER(discharge_location) LIKE '%NURSING%'
        OR UPPER(discharge_location) LIKE '%REHAB%'
        OR UPPER(discharge_location) LIKE '%FACILITY%'
        OR UPPER(discharge_location) LIKE '%SNF%'
        OR UPPER(discharge_location) LIKE '%ICF%'
        OR UPPER(discharge_location) LIKE '%LONG TERM CARE%'
        THEN 'Facility'
      ELSE 'Other'
    END AS outcome_category
  FROM cohort
)
SELECT
  outcome_category,
  COUNT(*) AS n,
  ROUND(quant[OFFSET(50)], 2) AS median_los_days,
  ROUND(quant[OFFSET(75)] - quant[OFFSET(25)], 2) AS iqr_los_days,
  ROUND(AVG(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) * 100, 1) AS pct_rank_14day
FROM (
  SELECT
    outcome_category,
    los_days,
    APPROX_QUANTILES(los_days, 100) AS quant
  FROM
    categorized
  WHERE outcome_category IN ('Home', 'Facility', 'Death')
  GROUP BY outcome_category, los_days
)
GROUP BY
  outcome_category, quant
ORDER BY outcome_category;