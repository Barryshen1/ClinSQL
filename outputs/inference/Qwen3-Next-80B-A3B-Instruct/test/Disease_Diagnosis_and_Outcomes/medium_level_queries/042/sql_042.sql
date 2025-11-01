WITH ami_patients AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND LOWER(did.long_title) LIKE '%acute myocardial infarction%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did2 ON d2.icd_code = did2.icd_code AND d2.icd_version = did2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (
          LOWER(did2.long_title) LIKE '%shock%'
          OR LOWER(did2.long_title) LIKE '%respiratory failure%'
        )
    )
),
los_categories AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    discharge_location,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 8 THEN '>=8 days'
    END AS los_group
  FROM ami_patients
),
median_los AS (
  SELECT 
    los_group,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
  FROM los_categories
  WHERE los_group IS NOT NULL
  GROUP BY los_group
),
discharge_breakdown AS (
  SELECT 
    los_group,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    discharge_location,
    COUNT(*) AS discharge_count
  FROM los_categories
  WHERE los_group IS NOT NULL
  GROUP BY los_group, discharge_location
)
SELECT 
  db.los_group,
  db.mortality_percent,
  ml.median_los_days,
  db.discharge_location,
  db.discharge_count
FROM discharge_breakdown db
INNER JOIN median_los ml ON db.los_group = ml.los_group
ORDER BY db.los_group, db.discharge_count DESC;