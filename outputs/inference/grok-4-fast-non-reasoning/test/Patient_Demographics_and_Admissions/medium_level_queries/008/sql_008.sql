WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Check for medicine careunit in any transfer
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t 
      WHERE t.subject_id = p.subject_id 
        AND t.hadm_id = a.hadm_id 
        AND STARTS_WITH(t.careunit, 'Med')
    ) THEN 1 ELSE 0 END AS is_medicine
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'DEAD/EXPIRED'
    WHEN discharge_location = 'HOME' THEN 'HOME'
    WHEN discharge_location IN ('SNF', 'REHAB', 'LTC', 'SHORE', 'SHOR', 'OTHER') THEN 'FACILITY'
    ELSE 'OTHER'
  END AS discharge_category,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS p90_los_days,
  -- % with LOS <= 7 days
  (SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_los_le_7_days
FROM eligible_admissions
WHERE is_medicine = 1
GROUP BY discharge_category
ORDER BY 
  CASE discharge_category 
    WHEN 'HOME' THEN 1 
    WHEN 'FACILITY' THEN 2 
    WHEN 'DEAD/EXPIRED' THEN 3 
    ELSE 4 
  END
;