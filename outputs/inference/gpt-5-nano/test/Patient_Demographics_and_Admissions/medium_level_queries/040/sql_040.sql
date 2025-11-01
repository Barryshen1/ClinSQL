WITH surgical_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pc
      WHERE pc.subject_id = a.subject_id
        AND pc.hadm_id = a.hadm_id
    )
),
annotated AS (
  SELECT
     s.subject_id,
     s.hadm_id,
     s.admittime,
     s.dischtime,
     s.discharge_location,
     s.hospital_expire_flag,
     CASE
       WHEN s.hospital_expire_flag = 1 THEN 'In-hospital death'
       WHEN LOWER(COALESCE(s.discharge_location,'')) LIKE '%snf%' 
            OR LOWER(COALESCE(s.discharge_location,'')) LIKE '%rehab%' 
            OR LOWER(COALESCE(s.discharge_location,'')) LIKE '%ltach%' THEN 'Facility'
       WHEN LOWER(COALESCE(s.discharge_location,'')) LIKE '%home%' THEN 'Home'
       ELSE 'Other'
     END AS discharge_group,
     TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) AS los_days
  FROM surgical_inpatients s
)
SELECT
  discharge_group,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_ge7_days,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS n_ge14_days,
  COUNT(*) AS total,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge7_days,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge14_days
FROM annotated
WHERE discharge_group IN ('Home','Facility','In-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;