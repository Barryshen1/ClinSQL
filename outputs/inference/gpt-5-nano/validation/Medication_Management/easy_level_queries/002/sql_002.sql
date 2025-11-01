WITH hospital AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    CASE
      WHEN p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL THEN
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),
amiodarone_prescriptions AS (
  SELECT
    pres.subject_id,
    pres.hadm_id,
    pres.starttime,
    pres.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  WHERE LOWER(pres.drug) LIKE '%amiodarone%'
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
)
SELECT
  CAST(q1_days AS FLOAT64) AS q1_days,
  CAST(q3_days AS FLOAT64) AS q3_days,
  CAST((q3_days - q1_days) AS FLOAT64) AS iqr_days
FROM (
  SELECT
    (quantiles)[OFFSET(1)] AS q1_days,
    (quantiles)[OFFSET(3)] AS q3_days
  FROM (
    SELECT APPROX_QUANTILES(duration_days, 4) AS quantiles
    FROM (
      SELECT
        TIMESTAMP_DIFF(pres.stoptime, pres.starttime, SECOND) / 86400.0 AS duration_days
      FROM hospital h
      JOIN amiodarone_prescriptions pres
        ON h.subject_id = pres.subject_id
       AND h.hadm_id = pres.hadm_id
      WHERE h.age_at_admission BETWEEN 59 AND 69
        AND UPPER(h.gender) = 'F'
    )
  )
) ;