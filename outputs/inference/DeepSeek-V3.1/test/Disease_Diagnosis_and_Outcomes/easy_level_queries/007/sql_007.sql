WITH ugib_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND icd_code IN (
      'K250','K252','K254','K256','K260','K262','K264','K266','K270','K272','K274','K276','K280','K282','K284','K286','K920','K921','K922'
    )) OR
    (icd_version = 9 AND icd_code IN (
      '53021','53100','53101','53120','53121','53140','53141','53160','53161','53200','53201','53220','53221','53240','53241','53260','53261','53300','53301','53320','53321','53340','53341','53360','53361','53400','53401','53420','53421','53440','53441','53460','53461','5780','5781','5789'
    ))
),

cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN ugib_codes u
    ON d.icd_code = u.icd_code AND d.icd_version = u.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num = 1
    AND a.dischtime IS NOT NULL
)

SELECT 
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM cohort;