WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 57 AND 67
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Diabetes%' OR long_title LIKE '%Heart failure%')
  )
),
glp1_ra_prescriptions AS (
  SELECT hadm_id, starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug LIKE '%GLP-1 RA%' OR drug LIKE '%Glucagon-like peptide-1 receptor agonist%'
),
time_frames AS (
  SELECT subject_id, hadm_id, admittime, dischtime,
         TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) AS first_48h_end,
         TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AS last_12h_start
  FROM patient_cohort
),
prevalence AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN grp.starttime BETWEEN pc.admittime AND tf.first_48h_end THEN pc.hadm_id END) AS count_first_48h,
    COUNT(DISTINCT CASE WHEN grp.starttime BETWEEN tf.last_12h_start AND pc.dischtime THEN pc.hadm_id END) AS count_last_12h,
    COUNT(DISTINCT pc.hadm_id) AS total_patients
  FROM patient_cohort pc
  INNER JOIN time_frames tf ON pc.hadm_id = tf.hadm_id
  LEFT JOIN glp1_ra_prescriptions grp ON pc.hadm_id = grp.hadm_id
)
SELECT 
  count_first_48h, 
  count_last_12h, 
  total_patients,
  (count_first_48h / total_patients) * 100 AS prevalence_first_48h,
  (count_last_12h / total_patients) * 100 AS prevalence_last_12h,
  ((count_last_12h / total_patients) - (count_first_48h / total_patients)) * 100 AS absolute_change,
  (((count_last_12h / total_patients) - (count_first_48h / total_patients)) / NULLIF((count_first_48h / total_patients), 0)) * 100 AS relative_change
FROM prevalence;