WITH first_service AS (
  SELECT
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
admissions_data AS (
  SELECT
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN first_service fs
    ON a.hadm_id = fs.hadm_id AND fs.rn = 1
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'elective'
    AND fs.curr_service = 'MED'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'death'
    WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE') THEN 'home'
    ELSE 'facility'
  END AS discharge_disposition,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY los) AS p90,
  COUNTIF(los <= 7) * 100.0 / COUNT(*) AS percentile_rank_7_days
FROM admissions_data
GROUP BY discharge_disposition;