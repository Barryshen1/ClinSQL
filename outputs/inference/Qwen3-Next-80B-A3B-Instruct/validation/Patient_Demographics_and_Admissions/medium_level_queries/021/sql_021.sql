WITH surgical_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND s.curr_service IN ('SURG', 'CSURG', 'TSURG', 'VSURG', 'NSURG', 'PSURG', 'ORTHO', 'NEUROSURG', 'CARDIO', 'VASC', 'URO', 'GYN', 'ENT', 'OPHTHAL', 'OR')
    AND a.dischtime >= a.admittime  -- ensure valid LOS
),
discharge_categories AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE') THEN 'Discharged home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'FACILITY', 'OTHER FACILITY', 'OTHER', 'DEAD', 'DECEASED') THEN 'Discharged to facility'
      ELSE 'Other'
    END AS discharge_category,
    EXTRACT(DAY FROM (dischtime - admittime)) AS los_days
  FROM surgical_admissions
  WHERE CASE
          WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
          WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE') THEN 'Discharged home'
          WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'FACILITY', 'OTHER FACILITY', 'OTHER', 'DEAD', 'DECEASED') THEN 'Discharged to facility'
          ELSE 'Other'
        END IN ('Discharged home', 'Discharged to facility', 'In-hospital mortality')
)
SELECT
  discharge_category,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(STDDEV(los_days), 2) AS sd_los,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_le_7
FROM discharge_categories
GROUP BY discharge_category
ORDER BY discharge_category;