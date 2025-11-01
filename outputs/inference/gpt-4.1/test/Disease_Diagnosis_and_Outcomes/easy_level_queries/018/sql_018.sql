SELECT
  STDDEV_POP(hospital_los) AS sd_hospital_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND d.seq_num = 1
    AND (
      -- ICD-10 hemorrhagic stroke codes
      (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^I60')
        OR REGEXP_CONTAINS(d.icd_code, r'^I61')
        OR REGEXP_CONTAINS(d.icd_code, r'^I62')
      ))
      -- ICD-9 hemorrhagic stroke codes
      OR (d.icd_version = 9 AND (
        d.icd_code = '430'
        OR d.icd_code = '431'
        OR REGEXP_CONTAINS(d.icd_code, r'^432')
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) > 0
);