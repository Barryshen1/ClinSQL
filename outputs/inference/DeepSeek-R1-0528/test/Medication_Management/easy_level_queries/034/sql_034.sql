SELECT 
  MAX(duration_days) AS max_duration_days
FROM (
  SELECT 
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pr.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pr.hadm_id = adm.hadm_id
  WHERE 
    pat.gender = 'F'
    AND EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age) BETWEEN 51 AND 61
    AND (
      LOWER(pr.drug) LIKE '%hydralazine%' 
      OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
    )
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
) AS valid_prescriptions;