WITH atorva_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CAST(TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) AS FLOAT64) / 3600.0 AS duration_hours
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
  WHERE
    LOWER(pat.gender) IN ('f', 'female')
    AND pat.anchor_age BETWEEN 75 AND 85
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    -- atorvastatin identification
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    -- high-intensity criterion: 40 mg or 80 mg
    AND (
      SAFE_CAST(p.dose_val_rx AS FLOAT64) IN (40, 80)
      OR LOWER(COALESCE(p.prod_strength, '')) LIKE '%40 mg%'
      OR LOWER(COALESCE(p.prod_strength, '')) LIKE '%80 mg%'
      OR LOWER(COALESCE(p.form_val_disp, '')) LIKE '%40 mg%'
      OR LOWER(COALESCE(p.form_val_disp, '')) LIKE '%80 mg%'
    )
    -- prefer mg units when available
    AND (p.dose_unit_rx IS NULL OR LOWER(p.dose_unit_rx) LIKE '%mg%')
    -- only valid durations
    AND p.stoptime > p.starttime
),
quartiles AS (
  SELECT APPROX_QUANTILES(duration_hours, 4) AS qs
  FROM atorva_prescriptions
  WHERE duration_hours IS NOT NULL
)
SELECT
  qs[OFFSET(1)] AS q1_hours,
  qs[OFFSET(3)] AS q3_hours,
  (qs[OFFSET(3)] - qs[OFFSET(1)]) AS iqr_hours
FROM quartiles;