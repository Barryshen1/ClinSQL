WITH filtered_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = '1' THEN 'Death'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN a.discharge_location IN ('REHAB/DISTINCT PART HOSP', 'LONG TERM CARE', 'OTHER FACILITY', 'HOSPICE', 'ACUTE HOSPITAL') THEN 'Facility'
      ELSE NULL
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND a.admission_type = 'TRANSFER FROM OTHER HOSPITAL'
)
SELECT
  discharge_category,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS q3,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_le_10
FROM filtered_data
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;