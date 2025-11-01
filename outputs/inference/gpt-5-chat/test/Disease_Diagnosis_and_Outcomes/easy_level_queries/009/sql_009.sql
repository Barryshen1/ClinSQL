WITH dx_groups AS (
  SELECT
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I2[0-5]'))
            OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(410|411|412|413|414)')) 
          THEN 1 ELSE 0 END) AS has_ihd_acs,
    MAX(CASE 
          WHEN (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J44'))
            OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(491|492|496)'))
          THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
filtered_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN dx_groups AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 75 AND 85
    AND dx.has_ihd_acs = 1
    AND dx.has_copd = 1
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS los_75th_percentile_days
FROM filtered_admissions;