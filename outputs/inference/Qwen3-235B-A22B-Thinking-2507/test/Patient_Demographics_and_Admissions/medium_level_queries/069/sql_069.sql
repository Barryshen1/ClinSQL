WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 0 THEN 'alive'
    WHEN hospital_expire_flag = 1 THEN 'dead'
  END AS mortality_status,
  AVG(CASE WHEN LOS_days >= 7 THEN 1.0 ELSE 0.0 END) AS proportion_ge7,
  (SELECT (COUNTIF(LOS_days <= 7) * 100.0) / COUNT(*) 
   FROM filtered_admissions) AS percentile_rank
FROM filtered_admissions
GROUP BY mortality_status;