WITH 
-- Identify patients with diabetes and heart failure
diabetes_heart_failure_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
  AND (dd.long_title LIKE '%Diabetes%' OR dd.long_title LIKE '%Heart Failure%')
),

-- Identify injectable GLP-1s
glp1_therapy AS (
  SELECT p.hadm_id, p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON p.hadm_id = ph.hadm_id AND p.pharmacy_id = ph.pharmacy_id
  WHERE p.drug LIKE '%GLP-1%' AND p.route = 'IV'
),

-- Calculate admission duration and first/last 72h
admission_duration AS (
  SELECT hadm_id, 
         TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS admission_duration,
         admittime AS admission_start,
         dischtime AS admission_end
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

first_last_72h AS (
  SELECT hadm_id,
         TIMESTAMP_ADD(admission_start, INTERVAL 72 HOUR) AS first_72h_end,
         TIMESTAMP_SUB(admission_end, INTERVAL 72 HOUR) AS last_72h_start
  FROM admission_duration
)

-- Calculate initiation rates in first and last 72h
SELECT 
  COUNT(DISTINCT CASE WHEN gt.starttime BETWEEN ad.admission_start AND TIMESTAMP_ADD(ad.admission_start, INTERVAL 72 HOUR) THEN gt.hadm_id END) AS first_72h_initiation,
  COUNT(DISTINCT CASE WHEN gt.starttime BETWEEN TIMESTAMP_SUB(ad.admission_end, INTERVAL 72 HOUR) AND ad.admission_end THEN gt.hadm_id END) AS last_72h_initiation
FROM diabetes_heart_failure_patients dhfp
JOIN glp1_therapy gt ON dhfp.hadm_id = gt.hadm_id
JOIN admission_duration ad ON dhfp.hadm_id = ad.hadm_id;