WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 78 AND 88
),
grouped AS (
  SELECT 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'Died' 
      ELSE 'Survived' 
    END AS survival_status,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
    APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los,
    NULL AS percentile_rank_10d
  FROM cohort
  GROUP BY survival_status
),
overall AS (
  SELECT 
    'Overall' AS survival_status,
    COUNT(*) AS num_admissions,
    NULL AS p50_los,
    NULL AS p75_los,
    NULL AS p90_los,
    NULL AS p95_los,
    (COUNTIF(los <= 10) * 100.0) / COUNT(*) AS percentile_rank_10d
  FROM cohort
)
SELECT * FROM grouped
UNION ALL
SELECT * FROM overall
ORDER BY survival_status DESC;  -- Order: Died, Survived, Overall;