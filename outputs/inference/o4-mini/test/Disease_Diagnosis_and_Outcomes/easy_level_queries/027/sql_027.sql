SELECT
  MAX(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.subject_id = d.subject_id
  AND a.hadm_id   = d.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code    = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 49 AND 59
  AND d.seq_num = 1
  AND LOWER(dd.long_title) LIKE '%upper gastrointestinal%'
  AND (
    LOWER(dd.long_title) LIKE '%bleed%'
    OR LOWER(dd.long_title) LIKE '%hemorrhage%'
  );