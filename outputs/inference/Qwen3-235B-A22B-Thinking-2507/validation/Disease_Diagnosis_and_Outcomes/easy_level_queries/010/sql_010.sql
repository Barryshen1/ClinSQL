WITH primary_copd AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND (
      (icd_version = 9 AND icd_code = '491.21')
      OR (icd_version = 10 AND icd_code = 'J441')
    )
),
filtered_admissions AS (
  SELECT
    adm.hadm_id,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN primary_copd pc
    ON adm.hadm_id = pc.hadm_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 49 AND 59
)
SELECT
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(25)] AS los_25th_percentile
FROM filtered_admissions;