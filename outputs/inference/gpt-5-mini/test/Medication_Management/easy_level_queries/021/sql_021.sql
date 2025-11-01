WITH atorva_pres AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    pr.dose_val_rx,
    pr.dose_unit_rx,
    pr.prod_strength,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    -- duration in days as fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND), 86400.0) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE
    -- female, age 75-85
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85

    -- inpatient prescription: starttime inside admission window
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.hadm_id IS NOT NULL
    AND pr.starttime >= a.admittime
    AND pr.starttime <= a.dischtime

    -- identify atorvastatin / Lipitor
    AND (
      LOWER(COALESCE(pr.drug, '')) LIKE '%atorvastatin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%lipitor%'
    )

    -- identify 40 mg or 80 mg strength via multiple possible fields
    AND (
      SAFE_CAST(pr.dose_val_rx AS INT64) IN (40, 80)
      OR SAFE_CAST(REGEXP_EXTRACT(LOWER(COALESCE(pr.prod_strength, '')), r'(\d+)') AS INT64) IN (40, 80)
      OR REGEXP_CONTAINS(LOWER(COALESCE(pr.drug, '')), r'(^|\D)(40|80)\s*mg(\D|$)')
    )

    -- positive duration only
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) > 0
),

quantiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS q_arr,
    COUNT(*) AS n_prescriptions
  FROM atorva_pres
)

SELECT
  q_arr[OFFSET(25)] AS q1_days,
  q_arr[OFFSET(50)] AS median_days,
  q_arr[OFFSET(75)] AS q3_days,
  q_arr[OFFSET(75)] - q_arr[OFFSET(25)] AS iqr_days,
  n_prescriptions
FROM quantiles;