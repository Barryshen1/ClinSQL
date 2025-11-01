WITH age_calc AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
first_service AS (
  SELECT
    hadm_id,
    TRIM(curr_service) AS curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
medicine_admissions AS (
  SELECT 
    ac.*
  FROM age_calc ac
  INNER JOIN first_service fs
    ON ac.hadm_id = fs.hadm_id
  WHERE fs.rn = 1
    AND fs.curr_service IN ('MED', 'CMED', 'ENDO', 'H&H', 'HTRANS', 'NCC', 'NEURO')
),
filtered AS (
  SELECT
    hospital_expire_flag,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400 AS los_days
  FROM medicine_admissions
  WHERE 
    gender = 'M'
    AND age_at_adm BETWEEN 57 AND 67
    AND admission_type IN ('EMERGENCY', 'URGENT')
)
SELECT
  hospital_expire_flag,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los,
  (COUNTIF(los_days <= 5) * 100.0 / COUNT(*)) AS percentile_rank_5
FROM filtered
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag;