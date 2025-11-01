WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.insurance,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_type = 'URGENT'
    AND a.insurance = 'Medicare'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 0
)

, outcomes AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'HOME') THEN 'Home'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location),
        r'SNF|REHAB|NURSING|SKILLED|FACILITY|LONG TERM|LTAC|ASSISTED|HOSPICE|INPATIENT|ACUTE|SWING BED|PSYCH|CHRONIC|INTERMEDIATE|RESIDENTIAL|BOARDING|FOSTER|GROUP|SHELTER|HALFWAY|SUPERVISED|RETIREMENT|CONVALESCENT|SUBACUTE|SUPPORTIVE|TRANSITIONAL|CARE HOME|HOME HEALTH|HOME CARE|HOME INFUSION|HOME DIALYSIS'
      ) THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome
  FROM cohort
)

, filtered AS (
  SELECT *
  FROM outcomes
  WHERE discharge_outcome IN ('Home', 'Facility', 'In-hospital death')
)

, stats AS (
  SELECT
    discharge_outcome,
    COUNT(*) AS n,
    AVG(los) AS los_mean,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS los_median,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS los_p75,
    APPROX_QUANTILES(los, 10)[OFFSET(9)] AS los_p90,
    -- Percentile of 10-day LOS: % of patients with LOS <= 10
    100.0 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_le_10
  FROM filtered
  GROUP BY discharge_outcome
)

SELECT
  discharge_outcome,
  n AS num_admissions,
  ROUND(los_mean,2) AS los_mean,
  los_median,
  los_p75,
  los_p90,
  ROUND(pct_los_le_10,1) AS pct_los_le_10
FROM stats
ORDER BY discharge_outcome;