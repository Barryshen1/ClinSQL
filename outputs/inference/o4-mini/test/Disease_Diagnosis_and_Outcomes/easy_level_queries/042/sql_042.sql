SELECT
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
   AND d.seq_num    = 1
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 78 AND 88
  AND d.icd_version = 9
  AND (
    STARTS_WITH(d.icd_code, '410')
    OR STARTS_WITH(d.icd_code, '411')
    OR STARTS_WITH(d.icd_code, '413')
    OR STARTS_WITH(d.icd_code, '414')
  );