WITH filtered_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'Died' 
      ELSE 'Alive' 
    END AS discharge_status
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.deathtime IS NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
)
SELECT 
  discharge_status,
  ROUND(AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) * 100, 2) AS prop_los_ge7_pct,
  ROUND(AVG(CASE WHEN los_days >= 14 THEN 1.0 ELSE 0 END) * 100, 2) AS prop_los_ge14_pct,
  ROUND(AVG(percentile_rank_for_10), 4) AS percentile_rank_10day_los
FROM (
  SELECT 
    *,
    PERCENT_RANK() OVER (PARTITION BY discharge_status ORDER BY los_days) AS percentile_rank_for_10
  FROM filtered_admissions
) ranked
WHERE los_days = 10 OR 1=0  -- Include all for proportions; filter irrelevant for percentile but compute over full partition
GROUP BY discharge_status
ORDER BY 
  CASE discharge_status WHEN 'Alive' THEN 1 WHEN 'Died' THEN 2 END;