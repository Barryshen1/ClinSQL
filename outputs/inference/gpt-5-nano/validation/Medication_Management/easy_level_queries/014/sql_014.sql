WITH target_subjects AS (
  -- Female patients aged 86-96 who had hospitalizations
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
statin_days AS (
  -- Expand each high-intensity atorvastatin prescription to per-day coverage
  SELECT a.hadm_id, day_date
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  JOIN target_subjects AS ts
    ON a.subject_id = ts.subject_id
  CROSS JOIN UNNEST(
      GENERATE_DATE_ARRAY(
        DATE(pr.starttime),
        DATE(IFNULL(pr.stoptime, a.dischtime)),
        INTERVAL 1 DAY
      )
    ) AS day_date
  WHERE LOWER(pr.drug) LIKE '%atorvastatin%'
    AND pr.dose_unit_rx = 'mg'
    AND pr.dose_val_rx BETWEEN 40 AND 80
    AND DATE(pr.starttime) <= DATE(IFNULL(pr.stoptime, a.dischtime))
)
SELECT MIN(days_on_high_intensity) AS min_high_intensity_duration_days
FROM (
  SELECT hadm_id, COUNT(DISTINCT day_date) AS days_on_high_intensity
  FROM statin_days
  GROUP BY hadm_id
) s;