SELECT STDDEV_SAMP(duration_days) AS sd_duration
FROM (
  SELECT 
    DATE_DIFF(prescriptions.stoptime, prescriptions.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions 
    ON prescriptions.hadm_id = admissions.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients 
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'F'
    AND EXTRACT(YEAR FROM admissions.admittime) - (patients.anchor_year - patients.anchor_age) BETWEEN 78 AND 88
    AND (
      prescriptions.drug LIKE '%lisinopril%' OR 
      prescriptions.drug LIKE '%enalapril%' OR 
      prescriptions.drug LIKE '%ramipril%' OR 
      prescriptions.drug LIKE '%perindopril%' OR 
      prescriptions.drug LIKE '%captopril%' OR 
      prescriptions.drug LIKE '%benazepril%' OR 
      prescriptions.drug LIKE '%moexipril%' OR 
      prescriptions.drug LIKE '%trandolapril%' OR 
      prescriptions.drug LIKE '%fosinopril%' OR 
      prescriptions.drug LIKE '%querson%' OR 
      prescriptions.drug LIKE '%zofenopril%' OR 
      prescriptions.drug LIKE '%ACE inhibitor%'
    )
    AND prescriptions.starttime IS NOT NULL
    AND prescriptions.stoptime IS NOT NULL
    AND prescriptions.stoptime >= prescriptions.starttime
    AND prescriptions.starttime BETWEEN admissions.admittime AND COALESCE(admissions.dischtime, CURRENT_DATETIME())
);