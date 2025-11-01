WITH prescription_durations AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, SECOND) / (24 * 3600) AS duration_days,
    pa.anchor_age,
    pa.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admittance_year,
    (pa.anchor_age - (pa.anchor_year - EXTRACT(YEAR FROM a.admittime))) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON pr.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients pa ON a.subject_id = pa.subject_id
  WHERE pa.gender = 'M'
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.stoptime IS NOT NULL
),
filtered_prescriptions AS (
  SELECT *
  FROM prescription_durations
  WHERE age_at_admission BETWEEN 62 AND 72
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3
  FROM filtered_prescriptions
)
SELECT
  ROUND(q3 - q1, 2) AS iqr_duration_days
FROM iqr_calc
LIMIT 1;