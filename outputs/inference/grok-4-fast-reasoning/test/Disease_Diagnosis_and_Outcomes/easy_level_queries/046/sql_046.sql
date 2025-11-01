SELECT
  STDDEV(los_days) AS sd_hospital_los_days
FROM (
  SELECT
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (
      p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year
    ) BETWEEN 43 AND 53
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9
        AND (
          d.icd_code = '430'
          OR d.icd_code = '431'
          OR d.icd_code LIKE '432%'
        ))
      OR
      (d.icd_version = 10
        AND (
          d.icd_code LIKE 'I60%'
          OR d.icd_code LIKE 'I61%'
          OR d.icd_code LIKE 'I62%'
        ))
    )
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) > 0
) AS cohort;