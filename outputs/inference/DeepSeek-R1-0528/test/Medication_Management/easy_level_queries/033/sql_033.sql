SELECT
  AVG(duration_days) AS avg_duration_days
FROM (
  SELECT
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pr.subject_id = adm.subject_id AND pr.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE
    REGEXP_CONTAINS(LOWER(pr.drug), r'losartan|valsartan|irbesartan|candesartan|telmisartan|eprosartan|olmesartan|azilsartan')
    AND p.gender = 'F'
    AND EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 77 AND 87
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
) AS ar_prescriptions;