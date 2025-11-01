SELECT
  AVG(
    TIMESTAMP_DIFF(
      CAST(a.dischtime AS TIMESTAMP),
      CAST(a.admittime AS TIMESTAMP),
      SECOND
    ) / 86400.0
  ) AS avg_los
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
WHERE
  d.seq_num = 1  -- Primary diagnosis
  AND p.gender = 'F'
  AND (
    (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('410', '411', '412', '413', '414'))
    OR
    (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25'))
  )
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
  ) BETWEEN 78 AND 88;