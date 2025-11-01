SELECT APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS p25_duration_days
FROM (
  SELECT 
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions ad 
    ON pa.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p 
    ON ad.hadm_id = p.hadm_id AND pa.subject_id = p.subject_id
  WHERE 
    pa.gender = 'M'
    AND pa.anchor_age BETWEEN 76 AND 86
    AND LOWER(p.route) IN ('iv', 'oral')
    AND LOWER(p.drug) LIKE '%nitrate%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND p.starttime BETWEEN ad.admittime AND ad.dischtime
);