WITH pneumonia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code BETWEEN '480' AND '48699')
    OR (icd_version = 10 AND (
           icd_code BETWEEN 'J12' AND 'J1299'
        OR icd_code BETWEEN 'J13' AND 'J1399'
        OR icd_code BETWEEN 'J14' AND 'J1499'
        OR icd_code BETWEEN 'J15' AND 'J1599'
        OR icd_code BETWEEN 'J16' AND 'J1699'
        OR icd_code BETWEEN 'J17' AND 'J1799'
        OR icd_code BETWEEN 'J18' AND 'J1899'
    ))
),
copd_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code BETWEEN '490' AND '49699')
    OR (icd_version = 10 AND (
           icd_code BETWEEN 'J40' AND 'J4499'
    ))
),
cohort AS (
  SELECT adm.subject_id, adm.hadm_id,
         DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN pneumonia_admissions p
    ON adm.hadm_id = p.hadm_id
  INNER JOIN copd_admissions c
    ON adm.hadm_id = c.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER () AS p75_hosp_los_days
FROM cohort
LIMIT 1;