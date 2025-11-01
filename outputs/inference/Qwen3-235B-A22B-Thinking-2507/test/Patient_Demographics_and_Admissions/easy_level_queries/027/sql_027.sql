WITH first_admissions AS (
  SELECT 
    a.*,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
filtered_los AS (
  SELECT 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los
  FROM first_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    a.rn = 1
    AND p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
)
SELECT 
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] - APPROX_QUANTILES(los, 1000)[OFFSET(250)] AS iqr
FROM filtered_los;