WITH first_service AS (
  SELECT
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
admissions_with_los AS (
  SELECT
    a.*,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN first_service fs
    ON a.hadm_id = fs.hadm_id AND fs.rn = 1
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
    AND fs.curr_service = 'MED'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'Death'
    WHEN discharge_location = 'HOME' THEN 'Home'
    ELSE 'Facility'
  END AS discharge_category,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los) AS p90,
  ROUND(SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS percent_le_10
FROM admissions_with_los
GROUP BY discharge_category;