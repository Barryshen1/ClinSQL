WITH surgical_admissions AS (
  SELECT DISTINCT a.*
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN (
    SELECT hadm_id, curr_service,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime DESC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp`.services
  ) s ON a.hadm_id = s.hadm_id AND s.rn = 1
  WHERE s.curr_service = 'SURG'
)
SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7_count,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge14_count,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS los_ge7_prop,
  ROUND(100.0 * SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) / COUNT(*), 2) AS los_ge14_prop
FROM (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    DATEDIFF(a.dischtime, a.admittime) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'Facility'
      ELSE NULL
    END AS discharge_category
  FROM surgical_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag IS NOT NULL
)
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;