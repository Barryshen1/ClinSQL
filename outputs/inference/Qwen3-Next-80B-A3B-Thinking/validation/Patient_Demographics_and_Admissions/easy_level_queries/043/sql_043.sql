SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY CAST(a.hospital_expire_flag AS INT64)) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY CAST(a.hospital_expire_flag AS INT64)) AS iqr
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61;