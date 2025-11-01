SELECT STDDEV(duration_days) AS sd_duration
FROM (
  SELECT 
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON pt.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON pt.subject_id = p.subject_id AND adm.hadm_id = p.hadm_id
  WHERE 
    pt.gender = 'F'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 73 AND 83
    AND LOWER(p.drug) LIKE '%nitrate%'
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
) AS durations;