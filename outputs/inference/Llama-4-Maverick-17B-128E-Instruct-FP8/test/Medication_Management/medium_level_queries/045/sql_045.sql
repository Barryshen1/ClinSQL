WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 54 AND 64
  AND a.admission_type = 'EMERGENCY'
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id AND dicd.long_title LIKE '%Diabetes%'
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id AND dicd.long_title LIKE '%Heart Failure%'
  )
),
meds AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime, p.starttime,
         CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
              WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' THEN 'Oral Agent'
              ELSE NULL END AS medication_type
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
  OR p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
),
med_counts AS (
  SELECT hadm_id, 
         SUM(CASE WHEN medication_type = 'Insulin' AND starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS insulin_first_12,
         SUM(CASE WHEN medication_type = 'Oral Agent' AND starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS oral_first_12,
         SUM(CASE WHEN medication_type = 'Insulin' AND starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS insulin_last_48,
         SUM(CASE WHEN medication_type = 'Oral Agent' AND starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS oral_last_48
  FROM meds
  GROUP BY hadm_id
),
prevalence AS (
  SELECT 
    COUNT(CASE WHEN insulin_first_12 > 0 THEN 1 END) AS insulin_users_first_12,
    COUNT(CASE WHEN oral_first_12 > 0 THEN 1 END) AS oral_users_first_12,
    COUNT(CASE WHEN insulin_last_48 > 0 THEN 1 END) AS insulin_users_last_48,
    COUNT(CASE WHEN oral_last_48 > 0 THEN 1 END) AS oral_users_last_48,
    COUNT(*) AS total_patients
  FROM med_counts
)
SELECT 
  SAFE_DIVIDE(insulin_users_first_12, total_patients) AS insulin_prevalence_first_12,
  SAFE_DIVIDE(oral_users_first_12, total_patients) AS oral_prevalence_first_12,
  SAFE_DIVIDE(insulin_users_last_48, total_patients) AS insulin_prevalence_last_48,
  SAFE_DIVIDE(oral_users_last_48, total_patients) AS oral_prevalence_last_48,
  SAFE_DIVIDE(insulin_users_last_48, total_patients) - SAFE_DIVIDE(insulin_users_first_12, total_patients) AS net_change_insulin,
  SAFE_DIVIDE(oral_users_last_48, total_patients) - SAFE_DIVIDE(oral_users_first_12, total_patients) AS net_change_oral
FROM prevalence;