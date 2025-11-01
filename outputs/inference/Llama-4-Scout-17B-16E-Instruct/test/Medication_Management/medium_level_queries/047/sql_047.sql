WITH 
-- Define medications of interest
meds_of_interest AS (
  SELECT 'Antidiabetic' AS med_type, drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE drug LIKE '%antidiabetic%' OR drug LIKE '%insulin%'
  UNION ALL
  SELECT 'Beta-blocker' AS med_type, drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE drug LIKE '%beta%' AND drug LIKE '%blocker%'
  UNION ALL
  SELECT 'ACEi/ARB/ARNI' AS med_type, drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE drug LIKE '%ACE%' OR drug LIKE '%ARB%' OR drug LIKE '%ARNI%'
  UNION ALL
  SELECT 'Loop diuretic' AS med_type, drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE drug LIKE '%loop%' AND drug LIKE '%diuretic%'
),

-- Identify patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
  AND (dd.long_title LIKE '%Diabetes%' OR dd.long_title LIKE '%Heart failure%')
),

-- Medication usage in first and last 24 hours
medication_usage AS (
  SELECT poi.subject_id, poi.hadm_id, poi.admittime, poi.dischtime, 
         mo.med_type, 
         CASE 
           WHEN p.starttime BETWEEN poi.admittime AND TIMESTAMP_ADD(poi.admittime, INTERVAL 1 DAY) THEN 'Initiated early'
           WHEN p.starttime BETWEEN TIMESTAMP_SUB(poi.dischtime, INTERVAL 1 DAY) AND poi.dischtime THEN 'Continued'
           WHEN p.starttime > TIMESTAMP_ADD(poi.admittime, INTERVAL 1 DAY) AND p.starttime < TIMESTAMP_SUB(poi.dischtime, INTERVAL 1 DAY) THEN 'Initiated late'
           WHEN p.stoptime BETWEEN poi.admittime AND poi.dischtime THEN 'Discontinued'
           ELSE 'Unknown'
         END AS medication_timing
  FROM patients_of_interest poi
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON poi.hadm_id = p.hadm_id
  JOIN meds_of_interest mo ON p.drug = mo.drug
)

-- Calculate percentages and counts
SELECT 
  med_type,
  COUNT(DISTINCT CASE WHEN medication_timing = 'Continued' THEN subject_id END) AS continued,
  COUNT(DISTINCT CASE WHEN medication_timing = 'Initiated late' THEN subject_id END) AS initiated_late,
  COUNT(DISTINCT CASE WHEN medication_timing = 'Discontinued' THEN subject_id END) AS discontinued,
  COUNT(DISTINCT subject_id) AS total_patients
FROM medication_usage
GROUP BY med_type;