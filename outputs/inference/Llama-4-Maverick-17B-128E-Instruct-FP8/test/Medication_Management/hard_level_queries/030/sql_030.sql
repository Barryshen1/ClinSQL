WITH 
acute_pancreatitis_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id, h.admittime, h.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.subject_id = d.subject_id AND h.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 71 AND 81
    AND diag.long_title LIKE '%Acute pancreatitis%'
),
med_complexity AS (
  SELECT ap.subject_id, ap.hadm_id, COUNT(DISTINCT p.drug) AS med_count
  FROM acute_pancreatitis_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON ap.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN ap.admittime AND TIMESTAMP_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY ap.subject_id, ap.hadm_id
),
tertiles AS (
  SELECT subject_id, hadm_id, med_count,
         NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM med_complexity
),
patient_outcomes AS (
  SELECT t.subject_id, t.hadm_id, t.tertile,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los,
         CASE WHEN a.deathtime IS NOT NULL AND a.deathtime <= a.dischtime THEN 1 ELSE 0 END AS in_hospital_mortality,
         a.dischtime
  FROM tertiles t
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
),
readmissions AS (
  SELECT po.subject_id, po.hadm_id, po.tertile, po.los, po.in_hospital_mortality,
         CASE 
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
             WHERE a2.subject_id = po.subject_id
               AND a2.admittime > po.dischtime
               AND a2.admittime <= TIMESTAMP_ADD(po.dischtime, INTERVAL 30 DAY)
           ) THEN 1 ELSE 0
         END AS readmitted
  FROM patient_outcomes po
)
SELECT tertile,
       AVG(los) AS avg_los,
       AVG(in_hospital_mortality) AS in_hospital_mortality_rate,
       AVG(readmitted) AS readmission_rate
FROM readmissions
GROUP BY tertile
ORDER BY tertile;