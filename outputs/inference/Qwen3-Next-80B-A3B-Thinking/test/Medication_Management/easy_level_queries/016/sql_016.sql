SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration) AS percentile_25
FROM (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year + pt.anchor_age) BETWEEN 76 AND 86
    AND pt.gender = 'M'
    AND LOWER(p.drug) LIKE '%nitrate%'
    AND p.route IN ('IV', 'Intravenous', 'Oral', 'PO')
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
) AS durations;