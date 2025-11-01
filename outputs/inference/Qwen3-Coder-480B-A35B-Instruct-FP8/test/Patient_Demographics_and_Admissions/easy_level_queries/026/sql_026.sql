WITH cabg_first_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.hadm_id = a.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
      ON a.subject_id = pat.subject_id
  WHERE
    -- CABG ICD codes
    (
      (p.icd_version = 9 AND p.icd_code IN ('1', '1.1', '1.2', '1.3', '1.4', '1.5'))
      OR
      (p.icd_version = 10 AND p.icd_code LIKE '021%')
    )
    AND LOWER(d.long_title) LIKE '%cabg%'
    -- Male patients aged 48–58
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
    -- First admission only
    AND a.admittime = (
      SELECT MIN(admittime)
      FROM physionet-data.mimiciv_3_1_hosp.admissions a2
      WHERE a2.subject_id = a.subject_id
    )
)

SELECT
  APPROX_QUANTILES(hospital_expire_flag, 4)[OFFSET(1)] AS mortality_25th_percentile
FROM
  cabg_first_admissions;