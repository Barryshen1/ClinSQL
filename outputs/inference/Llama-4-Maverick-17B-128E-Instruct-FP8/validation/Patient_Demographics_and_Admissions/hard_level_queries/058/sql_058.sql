WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, 
         p.anchor_age, 
         ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_num
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.admission_location = 'EMERGENCY ROOM ADMIT'
  AND a.insurance = 'Medicare'
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 50 AND 60
  AND a.hadm_id IN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_version = 10 
    AND d.icd_code IN (
      SELECT icd_code 
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
      WHERE long_title LIKE '%Gastrointestinal hemorrhage%' 
      OR long_title LIKE '%Lower gastrointestinal bleed%'
    )
    AND seq_num = 1  
  )
),
readmissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, admission_num,
         LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime,
         TIMESTAMP_DIFF(admittime, LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime), DAY) AS time_to_readmission
  FROM cohort
),
readmission_status AS (
  SELECT hadm_id, 
         CASE 
           WHEN time_to_readmission <= 30 THEN TRUE
           ELSE FALSE
         END AS readmitted
  FROM readmissions
  WHERE admission_num > 1
),
los AS (
  SELECT hadm_id, TIMESTAMP_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM cohort
)

SELECT 
  COUNT(CASE WHEN rs.readmitted THEN rs.hadm_id END) / COUNT(rs.hadm_id) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN rs.readmitted THEN los.length_of_stay END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT rs.readmitted THEN los.length_of_stay END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  COUNT(CASE WHEN rs.readmitted AND los.length_of_stay > 6 THEN rs.hadm_id END) / COUNT(CASE WHEN rs.readmitted THEN rs.hadm_id END) AS percent_los_gt_6_readmitted,
  COUNT(CASE WHEN NOT rs.readmitted AND los.length_of_stay > 6 THEN rs.hadm_id END) / COUNT(CASE WHEN NOT rs.readmitted THEN rs.hadm_id END) AS percent_los_gt_6_not_readmitted
FROM readmission_status rs
JOIN los ON rs.hadm_id = los.hadm_id;