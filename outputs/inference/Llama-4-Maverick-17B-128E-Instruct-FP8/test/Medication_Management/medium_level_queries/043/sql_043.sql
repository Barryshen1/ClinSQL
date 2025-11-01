WITH patient_cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Diabetes%' OR long_title LIKE '%Heart Failure%')
  )
),
medication_initiation AS (
  SELECT pc.subject_id, pc.hadm_id, 
         CASE 
           WHEN p.drug_type = 'MAIN' AND LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%insulin%' THEN 'Antidiabetics'
           WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%propranolol%' THEN 'Beta-blockers'
           WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%losartan%' THEN 'ACEi/ARBs/ARNI'
           WHEN LOWER(p.drug) LIKE '%furosemide%' THEN 'Loop Diuretics'
           ELSE NULL
         END AS medication_class,
         p.starttime,
         pc.intime AS icu_admission_time,
         pc.outtime AS icu_discharge_time
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON pc.hadm_id = p.hadm_id
  WHERE (LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%insulin%' 
         OR LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%propranolol%'
         OR LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%losartan%'
         OR LOWER(p.drug) LIKE '%furosemide%')
  AND p.starttime BETWEEN pc.intime AND pc.outtime
),
initiation_rates AS (
  SELECT medication_class,
         COUNT(DISTINCT CASE WHEN starttime <= icu_admission_time + INTERVAL 48 HOUR THEN subject_id END) AS initiated_first_48,
         COUNT(DISTINCT CASE WHEN starttime >= icu_discharge_time - INTERVAL 12 HOUR THEN subject_id END) AS initiated_last_12,
         COUNT(DISTINCT subject_id) AS total_patients
  FROM medication_initiation
  GROUP BY medication_class
)
SELECT medication_class,
       (initiated_first_48 / total_patients) * 100 AS initiation_rate_first_48,
       (initiated_last_12 / total_patients) * 100 AS initiation_rate_last_12,
       ((initiated_last_12 / total_patients) * 100) - ((initiated_first_48 / total_patients) * 100) AS net_change
FROM initiation_rates;